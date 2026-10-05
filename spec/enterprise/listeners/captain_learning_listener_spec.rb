require 'rails_helper'

RSpec.describe CaptainLearningListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:event) { Events::Base.new('conversation_resolved', Time.zone.now, conversation: conversation) }

  describe '#conversation_resolved' do
    context 'with an assistant that has FAQ learning on' do
      let!(:assistant) { create(:captain_assistant, account: account, config: { feature_faq: true }) }

      it 'enqueues the learning job' do
        expect(Captain::Llm::ReusableConversationFaqJob).to receive(:perform_later).with(conversation, assistant)

        listener.conversation_resolved(event)
      end

      # Learning rides on the `critical` queue's event dispatch, where a raise stops the listeners
      # after this one and fails the whole event. Enqueueing is all this listener may do.
      it 'does not call the service inline' do
        allow(Captain::Llm::ReusableConversationFaqJob).to receive(:perform_later)

        expect(Captain::Llm::ReusableConversationFaqService).not_to receive(:new)

        listener.conversation_resolved(event)
      end
    end

    it 'does nothing when the account has no assistant' do
      expect(Captain::Llm::ReusableConversationFaqJob).not_to receive(:perform_later)

      listener.conversation_resolved(event)
    end

    it 'does nothing when FAQ learning is off on the assistant' do
      create(:captain_assistant, account: account, config: { feature_faq: false })

      expect(Captain::Llm::ReusableConversationFaqJob).not_to receive(:perform_later)

      listener.conversation_resolved(event)
    end

    # Native CaptainListener handles a linked inbox, and generating FAQs twice for one conversation
    # is what stepping aside here avoids.
    it 'steps aside when the inbox has an assistant linked' do
      assistant = create(:captain_assistant, account: account, config: { feature_faq: true })
      create(:captain_inbox, inbox: inbox, captain_assistant: assistant)

      expect(Captain::Llm::ReusableConversationFaqJob).not_to receive(:perform_later)

      listener.conversation_resolved(event)
    end
  end
end
