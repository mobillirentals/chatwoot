require 'rails_helper'

RSpec.describe Captain::Llm::ReusableConversationFaqJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account, config: { feature_faq: true }) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, first_reply_created_at: Time.zone.now) }
  let(:faq_service) { instance_double(Captain::Llm::ReusableConversationFaqService, generate_suggestions: []) }
  let(:lock_manager) { instance_double(Redis::LockManager, lock: true, unlock: true) }

  before do
    conversation.update!(status: :resolved)
    allow(Redis::LockManager).to receive(:new).and_return(lock_manager)
    allow(Captain::Llm::ReusableConversationFaqService).to receive(:new).and_return(faq_service)
  end

  describe '#perform' do
    # The method name is the whole point of this job's existence: upstream renamed it in v4.18.0
    # and the listener kept calling the old one, which killed every resolved-conversation event.
    it 'generates suggestions for an inbox with no assistant linked' do
      expect(Captain::Llm::ReusableConversationFaqService).to receive(:new)
        .with(assistant, conversation)
        .and_return(faq_service)
      expect(faq_service).to receive(:generate_suggestions)

      described_class.perform_now(conversation, assistant)
    end

    it 'locks grouping by assistant and normalized account locale' do
      account.update!(locale: 'pt_BR')
      expected_key = "CAPTAIN_CONVERSATION_FAQ_LOCK::#{assistant.id}::pt"

      expect(lock_manager).to receive(:lock).with(expected_key, described_class::LOCK_TIMEOUT).and_return(true)
      expect(lock_manager).to receive(:unlock).with(expected_key)

      described_class.perform_now(conversation, assistant)
    end

    # Native CaptainListener takes over once the inbox has an assistant, so learning twice for the
    # same conversation is what this guard prevents.
    it 'stands aside when an assistant got linked to the inbox after enqueueing' do
      create(:captain_inbox, inbox: inbox, captain_assistant: assistant)

      expect(Captain::Llm::ReusableConversationFaqService).not_to receive(:new)

      described_class.perform_now(conversation.reload, assistant)
    end

    it 'does nothing when the conversation was reopened after enqueueing' do
      conversation.update!(status: :open)

      expect(Captain::Llm::ReusableConversationFaqService).not_to receive(:new)

      described_class.perform_now(conversation, assistant)
    end

    it 'does nothing when FAQ learning was turned off on the assistant' do
      assistant.update!(config: { feature_faq: false })

      expect(Captain::Llm::ReusableConversationFaqService).not_to receive(:new)

      described_class.perform_now(conversation, assistant.reload)
    end
  end
end
