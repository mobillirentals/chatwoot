# Blob-in, text-out audio transcription shared by voice-note attachments
# (Messages::AudioTranscriptionService) and voice-call recordings
# (Voice::CallTranscriptionService).
class Llm::SpeechToTextService < Llm::LegacyBaseOpenAiService
  include Integrations::LlmInstrumentation

  # OpenAI's transcription endpoint hard limit is 25 MB *decimal* (25_000_000), not
  # binary (25.megabytes = 26_214_400) — using the binary form leaks the 25.0–26.2 MB
  # range to the API as 413s. Long audio (~70+ min Opus) keeps the source audio but
  # skips transcription.
  BYTE_LIMIT = 25_000_000

  attr_reader :blob, :account, :transcription_model

  # Transcription runs on Captain's OpenAI credentials and consumes its response credits.
  def self.available_for?(account)
    return false unless account.feature_enabled?('captain_integration')
    return false if account.audio_transcriptions.blank?

    account.usage_limits[:captain][:responses][:current_available].positive?
  end

  def self.too_large?(blob)
    blob.present? && blob.byte_size > BYTE_LIMIT
  end

  AZURE_HOSTS = ['.openai.azure.com', '.cognitiveservices.azure.com'].freeze
  AZURE_API_VERSION = '2024-06-01'.freeze

  # `with_segments` pede o tempo de cada trecho, que e o que permite saber QUANDO cada frase foi
  # dita. So o whisper devolve isso: os modelos novos de transcricao (gpt-4o-transcribe e familia)
  # recusam `verbose_json` com 400 — testado contra o proprio recurso. Por isso o modelo tambem
  # muda junto, via CALL_TRANSCRIPTION_MODEL, em vez de valer para todo audio.
  def initialize(blob:, account:, with_segments: false)
    super()
    @blob = blob
    @account = account
    @with_segments = with_segments
    @transcription_model = resolve_model
    @client = azure_transcription_client if azure_endpoint?
  end

  def perform
    temp_file_path = fetch_audio_file
    resultado = nil

    File.open(temp_file_path, 'rb') do |file|
      resultado = instrument_audio_transcription(instrumentation_params(temp_file_path)) do
        # temperature: 0.0 minimises hallucinations on silence / near-silent
        # audio; non-zero values trigger spiraling repeats — well-documented
        # behaviour across OpenAI transcription models.
        parametros = { model: transcription_model, file: file }
        if @with_segments
          parametros[:response_format] = 'verbose_json'
          # Sem `temperature`, de proposito. Fixar 0.0 desliga o fallback de temperatura da propria
          # API, que e o mecanismo que quebra os loops de repeticao do whisper: medido no mesmo
          # audio, 0.0 devolveu 79 trechos e 189 palavras (um trecho repetido 66 vezes) contra 29
          # trechos e 87 palavras sem ele. Nos modelos novos, que nao tem esse fallback, 0.0 ajuda —
          # por isso a diferenca fica aqui e nao vale para todo audio.
        else
          parametros[:temperature] = 0.0
        end
        response = @client.audio.transcribe(parameters: parametros)
        @with_segments ? response : response['text']
      end
    end

    texto = @with_segments ? resultado['text'] : resultado
    account.increment_response_usage if texto.present?
    resultado
  ensure
    FileUtils.rm_f(temp_file_path) if temp_file_path.present?
  end

  private

  def resolve_model
    if @with_segments
      configurado = GlobalConfigService.load('CALL_TRANSCRIPTION_MODEL', 'whisper').to_s.strip
      return configurado if configurado.present?
    end

    Llm::FeatureRouter.resolve(feature: 'audio_transcription', account: account)[:model]
  end

  # O Azure não expõe transcrição na camada OpenAI-compatível: `/openai/v1/audio/transcriptions`
  # devolve 404 e só a rota clássica `/openai/deployments/{deployment}/audio/transcriptions`
  # responde (comprovado com o mesmo arquivo, chave e recurso). O gem cobre esse formato com
  # `api_type: :azure` (troca o header pra `api-key` e acrescenta `?api-version=`), mas aí o
  # `uri_base` precisa embutir o deployment — que varia por modelo. Por isso um client próprio
  # aqui em vez do que vem do LegacyBaseOpenAiService, compartilhado com o upload de PDF (esse
  # funciona no `/v1` e continua como está).
  def azure_endpoint?
    host = URI.parse(uri_base).host.to_s
    AZURE_HOSTS.any? { |suffix| host.end_with?(suffix) }
  rescue URI::InvalidURIError
    false
  end

  def azure_transcription_client
    OpenAI::Client.new(
      access_token: InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value,
      uri_base: "#{uri_base.chomp('/')}/deployments/#{transcription_model}",
      api_type: :azure,
      api_version: AZURE_API_VERSION,
      log_errors: Rails.env.development?
    )
  end

  def fetch_audio_file
    temp_dir = Rails.root.join('tmp/uploads/audio-transcriptions')
    FileUtils.mkdir_p(temp_dir)
    temp_file_name = "#{blob.key}-#{blob.filename}"

    if blob.filename.extension_without_delimiter.blank?
      extension = extension_from_content_type(blob.content_type)
      temp_file_name = "#{temp_file_name}.#{extension}" if extension.present?
    end

    temp_file_path = File.join(temp_dir, temp_file_name)

    File.open(temp_file_path, 'wb') do |file|
      blob.open do |blob_file|
        IO.copy_stream(blob_file, file)
      end
    end

    temp_file_path
  end

  def extension_from_content_type(content_type)
    subtype = content_type.to_s.downcase.split(';').first.to_s.split('/').last.to_s
    return if subtype.blank?

    {
      'x-m4a' => 'm4a',
      'x-wav' => 'wav',
      'x-mp3' => 'mp3'
    }.fetch(subtype, subtype)
  end

  def instrumentation_params(file_path)
    {
      span_name: 'llm.messages.audio_transcription',
      model: transcription_model,
      account_id: account&.id,
      feature_name: 'audio_transcription',
      file_path: file_path
    }
  end
end
