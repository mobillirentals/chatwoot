class Typebot::BridgeService
  VIEWER_URL = ENV.fetch('TYPEBOT_VIEWER_URL', 'https://botviewer.mobillirentals.com.br').freeze

  def initialize(payload, typebot_id)
    @payload      = payload.deep_symbolize_keys
    @typebot_id   = typebot_id
    @event        = @payload[:event]
    @content      = @payload[:content]
    @message_type = @payload[:message_type]
  end

  def perform
    return unless processable?

    conversation = find_conversation
    return unless conversation

    # Lock por conversa para evitar condição de corrida com múltiplos webhooks
    typebot_response = conversation.with_lock do
      attrs      = conversation.reload.additional_attributes
      session_id = attrs['typebot_session_id']

      # Idempotência: ignorar se essa mensagem já foi processada
      next if attrs['last_processed_message_id'] == @payload[:id].to_s

      # Não inicia nova sessão se um agente humano já respondeu
      next if session_id.blank? && human_replied?(conversation)

      response = if session_id.present?
        continue_or_restart(conversation, session_id)
      else
        start_session(conversation)
      end

      # Marcar como processada dentro do lock (atômico)
      if @payload[:id].present?
        conversation.update_columns(
          additional_attributes: conversation.additional_attributes.merge(
            'last_processed_message_id' => @payload[:id].to_s
          )
        )
      end

      response
    end

    return unless typebot_response

    persist_session(conversation, typebot_response['sessionId']) if typebot_response['sessionId']
    deliver_messages(conversation, typebot_response)
    cleanup_session(conversation) if typebot_response['input'].nil?
  end

  private

  def processable?
    return false unless @event == 'message_created' && @message_type == 'incoming'

    created_at = @payload[:created_at]
    if created_at.present?
      parsed = created_at.is_a?(Numeric) ? Time.at(created_at) : Time.parse(created_at.to_s)
      return false if parsed < 10.minutes.ago
    end

    true
  end

  def find_conversation
    display_id = @payload.dig(:conversation, :id)
    account_id = @payload.dig(:account, :id)
    Conversation.find_by(display_id: display_id, account_id: account_id)
  end

  def start_session(conversation)
    body = {
      prefilledVariables: {
        clientName:     conversation.contact&.name,
        conversationId: conversation.display_id
      }
    }.to_json

    response = http_client.post("/api/v1/typebots/#{@typebot_id}/startChat", body)
    JSON.parse(response.body) if response.success?
  rescue StandardError => e
    Rails.logger.error("[Typebot::BridgeService] startChat falhou: #{e.message}")
    nil
  end

  def continue_or_restart(conversation, session_id)
    response = http_client.post("/api/v1/sendMessage", { message: @content, sessionId: session_id }.to_json)

    if response.status == 404 || !response.success?
      cleanup_session(conversation)
      return start_session(conversation)
    end

    parsed = JSON.parse(response.body)

    # Quando o usuário digita texto livre enquanto o Typebot aguarda um botão,
    # ele retorna "Invalid message". Reiniciamos a sessão para evitar loop.
    first_text = extract_text(parsed['messages']&.first || {})
    if first_text.include?('Invalid message')
      cleanup_session(conversation)
      return start_session(conversation)
    end

    parsed
  rescue StandardError => e
    Rails.logger.error("[Typebot::BridgeService] sendMessage falhou: #{e.message}")
    nil
  end

  def persist_session(conversation, session_id)
    conversation.update_columns(
      additional_attributes: conversation.additional_attributes.merge(
        'typebot_session_id' => session_id,
        'typebot_id'         => @typebot_id
      )
    )
  end

  def cleanup_session(conversation)
    attrs = conversation.additional_attributes.except('typebot_session_id', 'typebot_id')
    conversation.update_columns(additional_attributes: attrs)
  end

  def deliver_messages(conversation, typebot_response)
    agent_bot   = conversation.inbox.agent_bot
    messages    = typebot_response['messages'] || []
    input       = typebot_response['input']
    is_choice   = input&.dig('type') == 'choice input'

    text_messages = messages
    button_label  = nil

    if is_choice && messages.any?
      *text_messages, last_msg = messages
      button_label = extract_text(last_msg).presence
    end

    text_messages.each do |msg|
      text = extract_text(msg)
      next if text.blank?

      conversation.messages.create!(
        content:      text,
        message_type: :outgoing,
        content_type: :text,
        account_id:   conversation.account_id,
        inbox_id:     conversation.inbox_id,
        sender:       agent_bot
      )
    end

    send_buttons(conversation, input, agent_bot, button_label) if is_choice
  end

  def extract_text(message)
    content = message['content']
    return content.to_s if content.is_a?(String)

    rich_text = content.is_a?(Hash) ? content['richText'] : nil
    return '' unless rich_text.is_a?(Array)

    rich_text.filter_map do |block|
      (block['children'] || []).filter_map { |c| c['text'].presence }.join
    end.reject(&:empty?).join("\n")
  end

  def send_buttons(conversation, input, agent_bot, label = nil)
    items = input['items']&.map do |item|
      text = item['content'].to_s
      { title: text, value: text }
    end
    return if items.blank?

    label ||= 'Como posso ajudar?'

    conversation.messages.create!(
      content:            label,
      message_type:       :outgoing,
      content_type:       :input_select,
      content_attributes: { items: items },
      account_id:         conversation.account_id,
      inbox_id:           conversation.inbox_id,
      sender:             agent_bot
    )
  end

  def human_replied?(conversation)
    conversation.messages.outgoing.where(sender_type: 'User').exists?
  end

  def http_client
    @http_client ||= Faraday.new(url: VIEWER_URL) do |f|
      f.request  :json
      f.adapter  Faraday.default_adapter
    end
  end
end
