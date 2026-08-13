# Nao segue o padrao OAuth dos outros (Slack/Linear/Notion) — a "conexao" aqui e um pareamento
# via QR code com o servico standalone whatsapp-number-checker/ (ver README naquela pasta).
# `show` funciona como status/poll (o front chama a cada ~2s enquanto nao conectado) e tambem
# e o unico lugar que sincroniza o Integrations::Hook nativo, unica fonte do badge
# Enabled/Disabled do card — nao existe um "create" separado porque o pareamento acontece do
# lado do servico Node, nao aqui.
class Api::V1::Accounts::Integrations::WhatsappNumberCheckerController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def show
    health = client.health
    connected = health[:whatsapp_connection] == 'connected'

    sync_hook(connected: connected, connected_number: health[:whatsapp_number])

    render json: {
      whatsapp_connection: health[:whatsapp_connection],
      connected: connected,
      connected_number: health[:whatsapp_number]
    }
  end

  def qr
    bytes = client.qr
    return head :no_content if bytes.blank?

    send_data bytes, type: 'image/png', disposition: 'inline'
  end

  def destroy
    client.logout
    fetch_hook&.destroy!
    head :ok
  end

  private

  def client
    @client ||= Integrations::WhatsappNumberChecker::Client.new
  end

  def fetch_hook
    Integrations::Hook.where(account: Current.account).find_by(app_id: 'whatsapp_number_checker')
  end

  # So mexe no Hook pra refletir o estado observado agora — desconexoes temporarias
  # (reconectando) desabilitam o hook mas nao o apagam; apagar de vez so acontece em #destroy,
  # junto com o logout de verdade no servico Node.
  def sync_hook(connected:, connected_number:)
    hook = fetch_hook

    if connected
      hook ||= Current.account.hooks.new(app_id: 'whatsapp_number_checker', hook_type: 'account')
      hook.status = 'enabled'
      hook.settings = { 'connected_number' => connected_number }
      hook.save!
    elsif hook&.enabled?
      hook.update!(status: 'disabled')
    end
  end
end
