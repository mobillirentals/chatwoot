module Enterprise::Message
  # Gives a burst of inbound messages time to land, so a customer typing five messages in a
  # row costs one analysis instead of five.
  SENTIMENT_ANALYSIS_DELAY = 1.minute

  def self.prepended(base)
    base.class_eval do
      has_one :call, class_name: 'Call', foreign_key: :message_id, dependent: :nullify, inverse_of: :message

      scope :with_call, -> { includes(call: [:contact, { inbox: :channel }]) }

      after_create_commit :schedule_captain_sentiment_analysis
      after_create_commit :schedule_captain_crm_warmup
      after_create_commit :complete_captain_team_handoff
    end
  end

  def push_event_data
    data = super
    data[:call] = call.push_event_data if content_type == 'voice_call' && call.present?
    data
  end

  private

  def schedule_captain_sentiment_analysis
    return unless incoming?
    return if private?
    return unless account.feature_enabled?('captain_integration')

    ::Captain::Conversation::SentimentAnalysisJob
      .set(wait: SENTIMENT_ANALYSIS_DELAY)
      .perform_later(conversation_id)
  end

  # The second half of AssignTeamTool. The tool picks the team but leaves the conversation
  # pending, because ResponseBuilderJob only posts the assistant's own words while it is — open
  # it any earlier and the reply is replaced by a canned handoff line. So the tool marks the
  # conversation, the job posts what the assistant said, and the handoff completes here, once
  # that message exists and the customer has actually been told what is happening.
  def complete_captain_team_handoff
    return unless outgoing?
    return if private?
    return unless sender.is_a?(::Captain::Assistant)

    # Reload first. ResponseBuilderJob loaded this conversation before the agent ran, and the tool
    # wrote the mark through a different instance of the same row — so the copy reachable from here
    # still has the attributes it had a minute ago, and the mark is invisible. Without this, every
    # transfer left the customer's conversation sitting in the bot's queue with a team on it and
    # nobody looking at it. (The job hit the same wall and re-reads :status straight from the row.)
    conversation.reload
    return unless conversation.pending?

    key = ::Captain::Tools::AssignTeamTool::HANDOFF_PENDING_KEY
    return if conversation.additional_attributes.to_h[key].blank?

    conversation.update!(
      additional_attributes: conversation.additional_attributes.to_h.except(key)
    )
    conversation.bot_handoff!
  end

  # Fires on the first customer message only: by the time they have said what they want, the CRM
  # answer is already on the conversation, so crm_lookup reads it instead of waiting on Bitrix.
  def schedule_captain_crm_warmup
    return unless incoming?
    return if private?
    return unless account.feature_enabled?('captain_integration')
    return unless first_incoming_message?

    ::Captain::Conversation::CrmWarmupJob.perform_later(conversation_id)
  end

  def first_incoming_message?
    conversation.messages.where(message_type: :incoming, private: false).limit(2).count == 1
  end

  def mark_pending_conversation_as_open_for_human_response
    return unless captain_pending_conversation?
    return unless human_response?
    return if private?
    return if template_bootstrap_message?

    previous_user = Current.user
    previous_executed_by = Current.executed_by
    Current.user = nil
    Current.executed_by = nil

    begin
      conversation.open!
      return unless conversation.saved_change_to_status?

      create_captain_auto_open_activity_message
    ensure
      Current.user = previous_user
      Current.executed_by = previous_executed_by
    end
  end

  def captain_pending_conversation?
    return false unless conversation.pending?

    ::CaptainInbox.exists?(inbox_id: conversation.inbox_id)
  end

  def template_bootstrap_message?
    additional_attributes['template_params'].present? &&
      !conversation.messages.incoming.exists?
  end

  def create_captain_auto_open_activity_message
    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale)
    )
  end
end
