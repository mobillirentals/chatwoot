require 'rails_helper'

RSpec.describe 'Conversation Audit', type: :model do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  before do
    conversation.class.send(:include, Enterprise::Audit::Conversation) if defined?(Enterprise::Audit::Conversation)
  end

  describe 'audit logging on destroy' do
    # Conversation deletion is now audited through the trash lifecycle services
    # (Trash::PurgeService emits a `purge` event). The raw :destroy must NOT
    # create its own audit row, otherwise a permanent deletion would be logged
    # twice (purge + destroy).
    it 'does not create a raw destroy audit' do
      skip 'Enterprise audit module not available' unless defined?(Enterprise::Audit::Conversation)

      expect do
        conversation.destroy!
      end.not_to(change(Audited::Audit, :count))
    end

    it 'does not create audit log for other actions by default' do
      skip 'Enterprise audit module not available' unless defined?(Enterprise::Audit::Conversation)

      expect do
        conversation.update!(priority: 'high')
      end.not_to(change(Audited::Audit, :count))
    end
  end
end
