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

  def initialize(blob:, account:)
    super()
    @blob = blob
    @account = account
    @transcription_model = Llm::FeatureRouter.resolve(feature: 'audio_transcription', account: account)[:model]
    @client = azure_transcription_client if azure_endpoint?
  end

  def perform
    temp_file_path = fetch_audio_file
    transcribed_text = nil

    File.open(temp_file_path, 'rb') do |file|
      transcribed_text = instrument_audio_transcription(instrumentation_params(temp_file_path)) do
        # temperature: 0.0 minimises hallucinations on silence / near-silent
        # audio; non-zero values trigger spiraling repeats — well-documented
        # behaviour across OpenAI transcription models.
        response = @client.audio.transcribe(
          parameters: {
            model: transcription_model,
            file: file,
            temperature: 0.0
          }
        )
        response['text']
      end
    end

    account.increment_response_usage if transcribed_text.present?
    transcribed_text
  ensure
    FileUtils.rm_f(temp_file_path) if temp_file_path.present?
  end

  private

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
