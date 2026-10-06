# Tela de conexão do WhatsApp não oficial: cria a sessão na ponte, mostra o QR code e, quando o
# número parear, cria a caixa.
#
# O navegador não alcança a ponte — ela é interna e não está publicada —, então o Rails faz a
# intermediação. É também o que mantém o segredo da ponte no servidor, fora do alcance do painel.
#
# A URL e o segredo da ponte vêm de configuração da instalação, não da caixa: na hora de parear
# ainda não existe caixa nenhuma para consultar.
class Api::V1::Accounts::Whatsapp::BaileysSessionsController < Api::V1::Accounts::BaseController
  attr_reader :caixa

  before_action :check_authorization
  before_action :exigir_ponte_configurada
  # Resolver a caixa aqui, e não dentro do bloco de `responder_com`: lá o rescue genérico
  # engoliria o RecordNotFound e devolveria 503 com texto de falha de envio.
  before_action :exigir_caixa_da_ponte, only: [:inbox_status, :inbox_qr, :reconnect]

  def show
    responder_com { http_ponte.get("/sessions/#{sessao}/health") }
  end

  # Abre uma sessão nova e devolve o id dela. Sem número: quem pareia só descobre o número ao ler
  # o QR, e a sessão o informa de volta assim que conecta.
  def create
    responder_com { http_ponte.post('/sessions', body: {}.to_json) }
  end

  # Devolve o QR como texto, não como imagem: assim o painel desenha com a mesma biblioteca que já
  # usa, sem depender de o Rails servir binário.
  def qr
    responder_com { http_ponte.get("/sessions/#{sessao}/qr?format=text") }
  end

  # Só aqui a caixa nasce, e o número vem de quem já pareou: a sessão sabe com qual número está
  # conectada, então ninguém precisa digitá-lo.
  def connect
    pareado = numero_pareado
    return render_could_not_create_error(I18n.t('errors.whatsapp.baileys.not_paired')) if pareado.blank?

    canal = montar_canal(pareado)
    return render_could_not_create_error(canal.errors.full_messages.join(', ')) unless canal.valid?

    canal.save!
    inbox = Current.account.inboxes.create!(name: params[:name].presence || "WhatsApp +#{pareado}", channel: canal)
    render json: { id: inbox.id, name: inbox.name, phone_number: canal.phone_number }
  end

  # Estado da conexão de uma caixa que já existe — o que a tela de configurações mostra.
  def inbox_status
    responder_com { http_ponte.get("/sessions/#{sessao_da_caixa}/health") }
  end

  # QR para reparear uma caixa que caiu.
  def inbox_qr
    responder_com { http_ponte.get("/sessions/#{sessao_da_caixa}/qr?format=text") }
  end

  # Derruba o pareamento atual e oferece QR novo, travado no número da caixa: parear outro número
  # faria a caixa seguir com o histórico e os contatos do antigo, mas enviando de outro lugar.
  def reconnect
    responder_com do
      http_ponte.post("/sessions/#{sessao_da_caixa}/repair",
                      body: { expected_number: numero_da_caixa }.to_json)
    end
  end

  private

  # Todas as ações daqui levam a criar uma caixa, então a permissão conferida é a de criar — e não
  # a derivada do nome da ação, que o Pundit tentaria (`connect?`, `qr?`) e o InboxPolicy não tem.
  def check_authorization
    authorize(Inbox, :create?)
  end

  def exigir_ponte_configurada
    return if Whatsapp::BaileysBridge.configurada?

    render json: { error: I18n.t('errors.whatsapp.baileys.bridge_not_configured') }, status: :unprocessable_entity
  end

  def montar_canal(pareado)
    Channel::Whatsapp.new(
      account: Current.account,
      phone_number: "+#{pareado}",
      provider: 'baileys',
      provider_config: {
        'bridge_url' => Whatsapp::BaileysBridge.url,
        'bridge_token' => Whatsapp::BaileysBridge.token,
        'webhook_verify_token' => Whatsapp::BaileysBridge.webhook_token,
        'session_id' => sessao
      }
    )
  end

  def sessao
    params[:session_id].to_s.gsub(/[^a-zA-Z0-9-]/, '')
  end

  def exigir_caixa_da_ponte
    @caixa = Current.account.inboxes.find(params[:inbox_id])
    canal = @caixa.channel
    return if canal.is_a?(Channel::Whatsapp) && canal.baileys?

    render json: { error: I18n.t('errors.whatsapp.baileys.not_a_bridge_inbox') }, status: :not_found
  end

  # Caixas criadas antes de a sessão ganhar id próprio continuam valendo pelo número.
  def sessao_da_caixa
    caixa.channel.provider_config['session_id'].presence || numero_da_caixa
  end

  def numero_da_caixa
    caixa.channel.phone_number.to_s.gsub(/\D/, '')
  end

  def numero_pareado
    resposta = http_ponte.get("/sessions/#{sessao}/health")
    return nil unless resposta.success?

    estado = resposta.parsed_response
    return nil unless estado['whatsapp_connection'] == 'connected'

    estado['whatsapp_number'].to_s.gsub(/\D/, '').presence
  rescue StandardError => e
    Rails.logger.error "[BAILEYS] nao consegui consultar a sessao #{sessao}: #{e.message}"
    nil
  end

  def http_ponte
    @http_ponte ||= Whatsapp::BaileysBridge.new
  end

  # Recebe um BLOCO, não a resposta pronta: passar `http_ponte.get(...)` como argumento faria a
  # chamada acontecer FORA deste método, e uma ponte fora do ar estouraria em 500 antes de o rescue
  # aqui ter chance de responder 503.
  #
  # A ponte já responde em JSON com o estado; repassar o corpo e o código evita traduzir duas vezes
  # a mesma informação (e o 202 de "QR ainda não saiu" tem significado para a tela).
  def responder_com
    resposta = yield
    render json: resposta.parsed_response, status: resposta.code
  rescue StandardError => e
    Rails.logger.error "[BAILEYS] ponte inacessivel: #{e.message}"
    render json: { error: I18n.t('errors.whatsapp.baileys.bridge_unreachable') }, status: :service_unavailable
  end
end
