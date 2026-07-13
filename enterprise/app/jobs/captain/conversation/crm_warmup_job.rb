# Warms the CRM cache off the critical path, so the customer's greeting never waits on Bitrix and
# the model's first crm_lookup reads from the conversation instead of the network.
class Captain::Conversation::CrmWarmupJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = ::Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return unless conversation.account.feature_enabled?('captain_integration')

    cache = ::Captain::CrmProfileCache.new(conversation: conversation)
    return if cache.cached.present?

    cache.refresh
  end
end
