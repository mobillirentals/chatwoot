# Learning from a resolved conversation is optional work, so it runs in its own job.
#
# The listener used to call the service inline, which put it inside EventDispatcherJob on the
# `critical` queue — and a listener that raises stops the listeners subscribed after it and fails
# the whole job, which Sidekiq then retries, republishing the event to every listener again. When
# the upgrade to v4.18.0 renamed the service method, that turned every single resolved conversation
# into a dead job: 5365 of them, and Captain::ReportingEventListener never ran once.
#
# Native Captain::Llm::ConversationFaqJob is the same shape, but it bails out unless the inbox has
# an assistant linked — which is precisely the case we learn in (see CaptainLearningListener for
# why the inbox stays unlinked). Hence a job of our own, with that one guard inverted.
class Captain::Llm::ReusableConversationFaqJob < MutexApplicationJob
  queue_as :low

  LOCK_TIMEOUT = 10.minutes

  retry_on_lock_conflict wait: 30.seconds, attempts: 30

  # Re-checked here rather than trusted from the listener: the job runs later, and a conversation
  # can be reopened, or an assistant linked to the inbox, in between.
  def perform(conversation, assistant)
    return unless conversation.resolved?
    return if conversation.inbox.captain_active?
    return if assistant.config['feature_faq'].blank?

    with_lock(lock_key(assistant, conversation), LOCK_TIMEOUT) do
      Captain::Llm::ReusableConversationFaqService.new(assistant, conversation).generate_suggestions
    end
  end

  private

  def lock_key(assistant, conversation)
    format(
      ::Redis::Alfred::CAPTAIN_CONVERSATION_FAQ_MUTEX,
      assistant_id: assistant.id,
      language: Captain::Llm::ConversationFaqService.language_for(conversation)
    )
  end
end
