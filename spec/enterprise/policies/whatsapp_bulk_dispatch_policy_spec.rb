# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::WhatsappBulkDispatchPolicy', type: :policy do
  subject(:whatsapp_bulk_dispatch_policy) { WhatsappBulkDispatchPolicy }

  let(:account) { create(:account) }
  let(:whatsapp_bulk_dispatch) { :whatsapp_bulk_dispatch }

  let(:custom_role) { create(:custom_role, account: account, permissions: ['campaign_manage']) }
  let(:agent_with_role) { create(:user) }
  let(:agent_with_role_account_user) do
    create(:account_user, user: agent_with_role, account: account, role: :agent, custom_role: custom_role)
  end
  let(:agent_with_role_context) do
    { user: agent_with_role, account: account, account_user: agent_with_role_account_user }
  end

  let(:agent_without_role) { create(:user) }
  let(:agent_without_role_account_user) do
    create(:account_user, user: agent_without_role, account: account, role: :agent)
  end
  let(:agent_without_role_context) do
    { user: agent_without_role, account: account, account_user: agent_without_role_account_user }
  end

  %i[index? show? create? update? confirm? destroy? template_spreadsheet?].each do |action|
    permissions action do
      context 'when agent has campaign_manage permission' do
        it { expect(whatsapp_bulk_dispatch_policy).to permit(agent_with_role_context, whatsapp_bulk_dispatch) }
      end

      context 'when agent does not have campaign_manage permission' do
        it { expect(whatsapp_bulk_dispatch_policy).not_to permit(agent_without_role_context, whatsapp_bulk_dispatch) }
      end
    end
  end
end
