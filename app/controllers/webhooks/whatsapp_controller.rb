class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :verify_meta_signature!, only: :process_payload
  before_action :verify_bridge_token!, only: :process_payload

  def process_payload
    if inactive_whatsapp_number?
      Rails.logger.warn("Rejected webhook for inactive WhatsApp number: #{params[:phone_number]}")
      render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity
      return
    end

    return head :ok if tracking_events_only?

    Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end

  private

  # Caixa atendida pela ponte Baileys nao tem assinatura da Meta para conferir
  # (meta_signature_verification_required? ja devolve false fora do whatsapp_cloud), e esta rota e
  # publica: sem isso, qualquer um poderia injetar mensagem de qualquer cliente na conversa. Entao
  # a ponte apresenta o segredo da propria caixa.
  def verify_bridge_token!
    return unless whatsapp_channel&.provider == 'baileys'

    esperado = whatsapp_channel.provider_config['webhook_verify_token'].to_s
    if esperado.blank?
      Rails.logger.error("[BAILEYS] caixa #{whatsapp_channel.phone_number} sem webhook_verify_token — webhook recusado")
      return head :unauthorized
    end

    return if ActiveSupport::SecurityUtils.secure_compare(esperado, request.headers['X-Bridge-Token'].to_s)

    Rails.logger.warn("[BAILEYS] token invalido no webhook de #{params[:phone_number]}")
    head :unauthorized
  end

  def tracking_events_only?
    return false unless params[:object] == 'whatsapp_business_account'

    changes = params.fetch(:entry, []).flat_map { |entry| entry.fetch(:changes, []) }
    changes.present? && changes.all? { |change| change[:field] == 'tracking_events' }
  end

  def valid_token?(token)
    channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
    whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
    token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
  end

  def meta_app_secrets
    [
      *channel_meta_app_secrets(whatsapp_channel),
      GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    ]
  end

  def whatsapp_channel
    @whatsapp_channel ||= whatsapp_business_payload_channel || Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  end

  def meta_signature_verification_required?
    return true if whatsapp_channel.blank?
    return false unless whatsapp_channel.provider == 'whatsapp_cloud'
    return true if channel_meta_app_secrets(whatsapp_channel).present?

    whatsapp_channel.provider_config['source'] == 'embedded_signup'
  end

  def whatsapp_business_payload_channel
    return unless params[:object] == 'whatsapp_business_account'

    metadata = params.dig(:entry, 0, :changes, 0, :value, :metadata)
    return if metadata.blank?

    Whatsapp::WebhookChannelFinderService.new(
      display_phone_number: metadata[:display_phone_number],
      phone_number_id: metadata[:phone_number_id]
    ).perform
  end

  def inactive_whatsapp_number?
    phone_number = params[:phone_number]
    return false if phone_number.blank?

    inactive_numbers = GlobalConfig.get_value('INACTIVE_WHATSAPP_NUMBERS').to_s
    return false if inactive_numbers.blank?

    inactive_numbers_array = inactive_numbers.split(',').map(&:strip)
    inactive_numbers_array.include?(phone_number)
  end
end
