# Captain learns from resolved conversations (CaptainListener) only once an assistant is linked
# to the inbox — and upstream ships that link coupled to two other things: answering customers,
# and a scheduled job that auto-resolves or hands off stale pending conversations. Our WhatsApp
# inbox already has an agent bot running triage, so a linked Captain would talk over it.
#
# So we leave the inbox unlinked, which keeps native Captain fully dormant (the scheduler iterates
# CaptainInbox, and the reply path needs inbox.captain_assistant), and do the learning here.
#
# This steps aside the moment an assistant IS linked to the inbox: native CaptainListener takes
# over for it, so the two never generate FAQs for the same conversation. That is the path to
# Captain actually answering customers later — no code to undo, just link it in the UI.
class CaptainLearningListener < BaseListener
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.inbox.captain_active?

    assistant = learning_assistant(conversation.account)
    return if assistant.blank?

    Captain::Llm::ReusableConversationFaqService.new(assistant, conversation).generate_and_deduplicate
  end

  private

  def learning_assistant(account)
    assistant = account.captain_assistants.first
    return if assistant.blank?
    return if assistant.config['feature_faq'].blank?

    assistant
  end
end
