require 'base64'

module Whatsapp::IncomingMessageServiceHelpers
  def download_attachment_file(attachment_payload)
    Down.download(inbox.channel.media_url(attachment_payload[:id]), headers: inbox.channel.api_headers)
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    }
  end

  def processed_params
    @processed_params ||= params
  end

  def account
    @account ||= inbox.account
  end

  def message_type
    messages_data.first[:type]
  end

  def message_content(message)
    # TODO: map interactive messages back to button messages in chatwoot
    message.dig(:text, :body) ||
      message.dig(:button, :text) ||
      message.dig(:interactive, :button_reply, :title) ||
      message.dig(:interactive, :list_reply, :title) ||
      message.dig(:name, :formatted_name)
  end

  def file_content_type(file_type)
    return :image if %w[image sticker].include?(file_type)
    return :audio if %w[audio voice].include?(file_type)
    return :video if ['video'].include?(file_type)
    return :location if ['location'].include?(file_type)
    return :contact if ['contacts'].include?(file_type)

    :file
  end

  def unprocessable_message_type?(message_type)
    %w[reaction ephemeral request_welcome].include?(message_type)
  end

  def processed_waid(waid)
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(waid, :cloud)
  end

  def whatsapp_phone_number(identifier)
    identifier = identifier.to_s
    return if identifier.blank?
    return unless identifier.match?(/\A\d{1,15}\z/)

    identifier
  end

  def error_webhook_event?(message)
    message.key?('errors')
  end

  def log_error(message)
    Rails.logger.warn "Whatsapp Error: #{message['errors'][0]['title']} - contact: #{message['from']}"
  end

  def process_in_reply_to(message)
    @in_reply_to_external_id = message['context']&.[]('id')
    @in_reply_to_external_id = resolve_reply_source_id(@in_reply_to_external_id) if @in_reply_to_external_id.present?
  end

  # Quando o cliente responde à PRÓPRIA mensagem, o WhatsApp manda o `context.id`
  # referenciando a mensagem pela identidade de usuário (user_id `BR.xxx`), enquanto
  # guardamos o wamid baseado no telefone. O match exato do `source_id` falha, mas o
  # id-da-mensagem (bloco final do wamid) é o mesmo. Aqui, se o exato não bater,
  # casamos por esse id-da-mensagem e devolvemos o `source_id` realmente armazenado.
  def resolve_reply_source_id(external_id)
    return external_id if @conversation.nil?
    return external_id if @conversation.messages.where(source_id: external_id).exists?

    target_hex = wamid_message_hex(external_id)
    return external_id if target_hex.blank?

    stored = @conversation.messages
                          .where.not(source_id: nil)
                          .reorder(created_at: :desc)
                          .limit(100)
                          .pluck(:source_id)
                          .find { |sid| wamid_message_hex(sid) == target_hex }
    stored || external_id
  end

  # Extrai o id-da-mensagem (último bloco hex) de um wamid, que é estável
  # independente da identidade (telefone x user_id) embutida no id.
  def wamid_message_hex(source_id)
    return nil if source_id.blank? || !source_id.to_s.start_with?('wamid.')

    decoded = Base64.decode64(source_id.to_s.delete_prefix('wamid.'))
    decoded.scan(/[0-9A-Fa-f]{16,}/).last
  end

  def referral_attributes(message)
    return {} if outgoing_echo

    message[:referral]&.to_h&.deep_stringify_keys || {}
  end

  def find_message_by_source_id(source_id)
    return unless source_id

    @message = Message.find_by(source_id: source_id)
  end

  def lock_message_source_id!
    return false if messages_data.blank?

    Whatsapp::MessageDedupLock.new(messages_data.first[:id]).acquire!
  end
end
