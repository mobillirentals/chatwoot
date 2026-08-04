class BotFlow::BridgeService
  def initialize(payload, _bot_id = nil)
    @payload      = payload.deep_symbolize_keys
    @event        = @payload[:event]
    @content      = @payload[:content]
    @message_type = @payload[:message_type]
  end

  def perform
    return unless processable?

    conversation = find_conversation
    return unless conversation
    return if human_owns_conversation?(conversation)
    return if conversation.inbox.out_of_office?

    skip = false

    conversation.with_lock do
      attrs = conversation.reload.additional_attributes

      if attrs['last_processed_message_id'] == @payload[:id].to_s
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

    result = BotFlow::Engine.step(conversation, effective_content)
    return unless result

    deliver(conversation, result)

    return unless result[:end_session]

    resolve_conversation(conversation)
    cleanup_session(conversation)
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

  # A human already owns this conversation — stay silent. Without this, a
  # conversation an agent starts manually (e.g. sending a template and
  # self-assigning before the customer's first reply) has no bot_state yet,
  # so the customer's reply falls through to the 'start' state and the bot
  # runs its full greeting/menu flow on top of the agent already talking to
  # them. Once the bot itself hands off, bot_state is already 'atendente'
  # (see Engine#handle_atendente) by the time round-robin can populate
  # assignee_id, so this check never interferes with that path.
  def human_assigned?(conversation)
    conversation.assignee_id.present?
  end

  # Um humano já dono da conversa: o bot fica em silêncio (ver comentário de
  # human_assigned? acima). Toda conversa nova nasce 'pending' nesta inbox
  # (bot ativo — Conversation#set_active_bot_conversation), e só o handoff do
  # próprio bot (Engine#hand_off_to_human) marca 'open'. Uma conversa que o
  # agente inicia sozinho (ex.: mandando template e se autoatribuindo) nunca
  # passa pelo bot, então fica presa em 'pending' pra sempre — aqui, na
  # primeira resposta do cliente, abrimos ela.
  def human_owns_conversation?(conversation)
    return false unless human_assigned?(conversation)

    open_pending_conversation(conversation)
    true
  end

  def open_pending_conversation(conversation)
    return unless conversation.pending?

    conversation.update!(status: :open)
  end

  def find_conversation
    display_id = @payload.dig(:conversation, :id)
    account_id = @payload.dig(:account, :id)
    Conversation.find_by(display_id: display_id, account_id: account_id)
  end

  # Conteúdo textual da mensagem. Se o cliente compartilhou um pin de localização
  # (mensagem sem texto, só com attachment de localização), devolve uma descrição
  # para o fluxo reconhecer como resposta válida (ex.: na Emergência).
  def effective_content
    return @content if @content.present?

    location_description
  end

  def location_description
    return nil if @payload[:id].blank?

    message  = Message.find_by(id: @payload[:id])
    location = message&.attachments&.detect { |a| a.file_type == 'location' }
    return nil unless location

    label = location.fallback_title.presence ||
            [location.coordinates_lat, location.coordinates_long].compact.join(', ')
    "📍 Localização recebida: #{label}"
  end

  def deliver(conversation, result)
    agent_bot = conversation.inbox.agent_bot
    messages  = result[:messages] || []
    buttons   = result[:buttons]  || []

    # When there are buttons, the last message becomes the interactive label;
    # all preceding messages are sent as plain :text (markdown renders in dashboard).
    # When there's only 1 message + buttons, send it as :text AND use a neutral
    # label so markdown is never swallowed into an input_select.
    if buttons.any? && messages.count > 1
      *text_msgs, label_msg = messages
    else
      text_msgs = messages
      label_msg = nil
    end

    text_msgs.each do |text|
      next if text.blank?

      conversation.messages.create!(
        content:      text,
        message_type: :outgoing,
        content_type: :text,
        account_id:   conversation.account_id,
        inbox_id:     conversation.inbox_id,
        sender:       agent_bot
      )

      # Small pause so the WhatsApp Cloud API delivers messages in the correct
      # order. SendReplyJob is async; without this, the button message can
      # arrive before the preceding text messages.
      sleep(0.4) if buttons.any?
    end

    return unless buttons.any?

    label = label_msg.presence || 'O que deseja fazer?'
    conversation.messages.create!(
      content:            label,
      message_type:       :outgoing,
      content_type:       :input_select,
      content_attributes: { items: buttons },
      account_id:         conversation.account_id,
      inbox_id:           conversation.inbox_id,
      sender:             agent_bot
    )
  end

  def resolve_conversation(conversation)
    return if conversation.resolved?

    Current.user = conversation.inbox.agent_bot
    conversation.update!(status: :resolved)
  rescue StandardError => e
    Rails.logger.error("[BotFlow::BridgeService] resolver conversa falhou: #{e.message}")
  ensure
    Current.user = nil
  end

  def cleanup_session(conversation)
    attrs = conversation.additional_attributes.except('bot_state', 'bot_crm', 'last_processed_message_id')
    conversation.update_columns(additional_attributes: attrs)
  end
end
