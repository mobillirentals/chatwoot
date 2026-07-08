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

    # Lock curto: apenas ler estado e marcar idempotência — NÃO inclui a chamada HTTP ao Typebot
    # (incluir o HTTP no lock causaria deadlock: Typebot dispara webhook → Chatwoot tenta
    #  UPDATE conversation → aguarda a própria trava → statement timeout)
    session_id = nil
    skip       = false

    conversation.with_lock do
      attrs      = conversation.reload.additional_attributes
      session_id = attrs['typebot_session_id']

      if attrs['last_processed_message_id'] == @payload[:id].to_s
        skip = true
        next
      end

      if session_id.blank? && human_replied?(conversation)
        skip = true
        next
      end

      if @payload[:id].present?
        conversation.update_columns(
          additional_attributes: conversation.additional_attributes.merge(
            'last_processed_message_id' => @payload[:id].to_s
          )
        )
      end
    end

    return if skip

    # Chamada HTTP ao Typebot FORA do lock
    typebot_response = if session_id.present?
      continue_or_restart(conversation, session_id)
    else
      start_session(conversation)
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
        conversationId: conversation.display_id,
        accountId:      conversation.account_id,
        chatwootToken:  ENV.fetch('CHATWOOT_BOT_API_TOKEN', '')
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
    first_text = extract_text(parsed['messages']&.first || {}, formatted: false)
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

  def extract_text(message, formatted: true)
    content = message['content']
    return content.to_s if content.is_a?(String)

    rich_text = content.is_a?(Hash) ? content['richText'] : nil
    return '' unless rich_text.is_a?(Array)

    rich_text.map { |block| render_rich_block(block, formatted: formatted) }.join("\n")
  end

  def render_rich_block(block, formatted: true)
    case block['type']
    when 'a'
      # Nó de link — usa URL como texto (WhatsApp torna clicável automaticamente)
      (block['url'] || block['children']&.map { |c| c['text'].to_s }&.join).to_s
    else
      (block['children'] || []).map { |child| render_rich_child(child, formatted: formatted) }.join
    end
  end

  def render_rich_child(child, formatted: true)
    text = child['text'].to_s
    return '' if text.empty?
    return text unless formatted

    # O Chatwoot processa o conteúdo via WhatsAppRenderer (CommonMarker) antes de enviar ao WhatsApp:
    #   **text** → strong → *text* no WhatsApp (negrito)
    #   _text_  → emph  → _text_ no WhatsApp (itálico)
    #   ~text~  → texto puro (extensão não habilitada) → ~text~ no WhatsApp (riscado)
    # underline: sem suporte no WhatsApp, ignorado intencionalmente.
    text = "~#{text}~" if child['strikethrough']
    if child['bold']
      text = "**#{text}**"
    elsif child['italic']
      text = "_#{text}_"
    end
    text
  end

  def send_buttons(conversation, input, agent_bot, label = nil)
    items = input['items']&.map do |item|
      text = item['content'].to_s
      { title: text, value: text }
    end
    return if items.blank?

    label = label&.gsub(/[*_~]/, '')&.strip.presence || 'Como posso ajudar?'

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
