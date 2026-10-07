require 'net/http'

# Recado de voz da chamada, que vive inteiro na Meta — não há nada disso no nosso banco.
#
# Com as chamadas de entrada desligadas, a Meta recusa a ligação na hora. Com o recado ativo, antes
# de recusar ela toca um aviso e deixa o cliente gravar; a gravação chega na conversa como mensagem
# de áudio comum, pelo mesmo webhook das outras — e por isso já cai no caminho de transcrição.
class Whatsapp::CallVoicemailService
  # A Meta exige exatamente isto: OGG com codec Opus, menos de 60 s. Arquivo fora disso é recusado
  # no envio, não na hora de tocar — então vale conferir antes de gastar a viagem.
  ANNOUNCEMENT_MIME = 'audio/ogg'.freeze
  UPLOAD_USE_CASE = 'call_voicemail_announcement'.freeze
  TRIGGERS = %w[REJECT TIMEOUT].freeze

  class Error < StandardError; end

  pattr_initialize [:channel!]

  def fetch
    resposta = graph_get("#{phone_number_id}/settings")
    (resposta.dig('calling', 'voicemail') || {}).slice('status', 'triggers', 'audio')
  end

  def enable(io:, filename:, triggers: ['REJECT'], timeout_seconds: 20)
    triggers = Array(triggers).map { |t| t.to_s.upcase }.intersection(TRIGGERS).presence || ['REJECT']
    media_id = upload_announcement(io, filename)

    audio = { announcement_media_id: media_id }
    audio[:timeout_seconds] = timeout_seconds.to_i.clamp(0, 30) if triggers.include?('TIMEOUT')

    apply(status: 'ENABLED', triggers: triggers, audio: { default: audio })
    media_id
  end

  def disable
    apply(status: 'DISABLED')
  end

  # O áudio guardado na Meta só sai com o token, que não pode ir para o navegador — então quem quer
  # ouvir o recado atual passa por aqui e recebe os bytes.
  def announcement_bytes
    media_id = fetch.dig('audio', 'default', 'announcement_media_id')
    return if media_id.blank?

    url = graph_get(media_id.to_s)['url']
    return if url.blank?

    baixar(url)
  end

  private

  def phone_number_id
    channel.provider_config['phone_number_id']
  end

  def token
    channel.provider_config['api_key']
  end

  # Mesma variável que o WhatsappCloudService já usa: deixa o host trocável (ambiente de teste,
  # dublê local) em vez de fixo no código.
  def graph_base
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')}"
  end

  def graph_get(caminho)
    resposta = HTTParty.get("#{graph_base}/#{caminho}", headers: { 'Authorization' => "Bearer #{token}" })
    raise Error, meta_message(resposta) unless resposta.success?

    resposta.parsed_response.is_a?(Hash) ? resposta.parsed_response : {}
  end

  def apply(config)
    resposta = HTTParty.post(
      "#{graph_base}/#{phone_number_id}/settings",
      headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' },
      body: { calling: { voicemail: config } }.to_json
    )
    raise Error, meta_message(resposta) unless resposta.success?

    true
  end

  # O multipart do HTTParty não monta o arquivo nesta versão — a Meta responde "The parameter file
  # is required" com o corpo aparentemente certo. Montado à mão, funciona.
  def upload_announcement(io, filename)
    limite = "----chatwoot#{SecureRandom.hex(8)}"
    uri = URI("#{graph_base}/#{phone_number_id}/media")

    requisicao = Net::HTTP::Post.new(uri)
    requisicao['Authorization'] = "Bearer #{token}"
    requisicao['Content-Type'] = "multipart/form-data; boundary=#{limite}"
    requisicao.body = multipart_body(io, filename, limite)

    resposta = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(requisicao) }
    dados = parse(resposta.body)
    raise Error, meta_message(resposta) if dados['id'].blank?

    dados['id']
  end

  def multipart_body(io, filename, limite)
    corpo = +''
    { 'messaging_product' => 'whatsapp', 'use_case' => UPLOAD_USE_CASE, 'type' => ANNOUNCEMENT_MIME }.each do |k, v|
      corpo << "--#{limite}\r\nContent-Disposition: form-data; name=\"#{k}\"\r\n\r\n#{v}\r\n"
    end
    corpo << "--#{limite}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
    corpo << "Content-Type: #{ANNOUNCEMENT_MIME}\r\n\r\n"
    corpo.b + io.read.b + "\r\n--#{limite}--\r\n".b
  end

  def baixar(url)
    resposta = HTTParty.get(url, headers: { 'Authorization' => "Bearer #{token}" })
    resposta.success? ? resposta.body : nil
  end

  def parse(corpo)
    JSON.parse(corpo.to_s)
  rescue JSON::ParserError
    {}
  end

  def meta_message(resposta)
    erro = parse(resposta.body)['error'] || {}
    erro['error_user_msg'].presence || erro['message'].presence || "Meta respondeu #{resposta.code}"
  end
end
