class Captain::Conversation::SentimentAnalysisJob < ApplicationJob
  queue_as :low

  # The job is already debounced by a delay on enqueue, but a burst of inbound messages
  # still enqueues one job each. This keeps the last one from re-analysing what the first
  # one just did. Captain's Redis cache (keyed on last_activity_at) is the backstop.
  THROTTLE_WINDOW = 90.seconds

  def perform(conversation_id)
    conversation = ::Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return unless conversation.open?
    return unless conversation.account.feature_enabled?('captain_integration')
    return if throttled?(conversation)

    result = analyse(conversation)
    return if result.blank? || result[:error].present?

    update_sentiment(conversation, result[:sentiment])
  end

  private

  def analyse(conversation)
    ::Captain::SentimentService.new(
      account: conversation.account,
      conversation_display_id: conversation.display_id
    ).perform
  end

  def update_sentiment(conversation, sentiment)
    changed = conversation.captain_sentiment != sentiment

    conversation.update!(captain_sentiment: sentiment, captain_sentiment_updated_at: Time.current)

    # captain_sentiment is not in Conversation#list_of_keys, so the update above does not
    # broadcast on its own. Dispatch only when the emoji would actually change.
    conversation.dispatch_conversation_updated_event if changed
  end

  def throttled?(conversation)
    conversation.captain_sentiment_updated_at.present? &&
      conversation.captain_sentiment_updated_at > THROTTLE_WINDOW.ago
  end
end
