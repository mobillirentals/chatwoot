# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::CampaignPolicy', type: :policy do
  subject(:campaign_policy) { CampaignPolicy }

  let(:account) { create(:account) }
  let(:campaign) { :campaign }

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

  %i[index? show? create? update? destroy?].each do |action|
    permissions action do
      context 'when agent has campaign_manage permission' do
        it { expect(campaign_policy).to permit(agent_with_role_context, campaign) }
      end

      context 'when agent does not have campaign_manage permission' do
        it { expect(campaign_policy).not_to permit(agent_without_role_context, campaign) }
      end
    end
  end
end
