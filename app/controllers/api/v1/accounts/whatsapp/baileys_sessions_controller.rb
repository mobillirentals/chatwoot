# Tela de conexão do WhatsApp não oficial: cria a sessão na ponte, mostra o QR code e, quando o
# número parear, cria a caixa.
#
# O navegador não alcança a ponte — ela é interna e não está publicada —, então o Rails faz a
# intermediação. É também o que mantém o segredo da ponte no servidor, fora do alcance do painel.
#
# A URL e o segredo da ponte vêm de configuração da instalação, não da caixa: na hora de parear
# ainda não existe caixa nenhuma para consultar.
class Api::V1::Accounts::Whatsapp::BaileysSessionsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :exigir_ponte_configurada

  def show
    responder_com { http_ponte.get("/sessions/#{numero}/health") }
  end

  # Abre (ou reaproveita) a sessão do número e devolve o estado dela.
  def create
    responder_com { http_ponte.post('/sessions', body: { id: numero }.to_json) }
  end

  # Devolve o QR como texto, não como imagem: assim o painel desenha com a mesma biblioteca que já
  # usa, sem depender de o Rails servir binário.
  def qr
    responder_com { http_ponte.get("/sessions/#{numero}/qr?format=text") }
  end

  # Só aqui a caixa nasce — e a validação do canal confere no /health se a ponte está mesmo pareada
  # com este número, então uma caixa criada apontando para a sessão errada não passa.
  def connect
    canal = Channel::Whatsapp.new(
      account: Current.account,
      phone_number: telefone_formatado,
      provider: 'baileys',
      provider_config: {
        'bridge_url' => Whatsapp::BaileysBridge.url,
        'bridge_token' => Whatsapp::BaileysBridge.token,
        'webhook_verify_token' => Whatsapp::BaileysBridge.webhook_token
      }
    )

    return render_could_not_create_error(canal.errors.full_messages.join(', ')) unless canal.valid?

    canal.save!
    inbox = Current.account.inboxes.create!(name: params[:name].presence || "WhatsApp #{telefone_formatado}", channel: canal)
    render json: { id: inbox.id, name: inbox.name, phone_number: canal.phone_number }
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

  def numero
    params[:phone_number].to_s.gsub(/\D/, '')
  end

  def telefone_formatado
    "+#{numero}"
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
