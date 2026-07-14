# Warms the CRM cache off the critical path, so the greeting never waits on Bitrix/Asaas and
# by the time the customer picks "Financeiro" the answer is usually already on the conversation.
class BotFlow::CrmWarmupJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    crm = BotFlow::CrmLookup.fetch(conversation)
    conversation.update_columns(
      additional_attributes: conversation.additional_attributes.merge('bot_crm' => crm.transform_keys(&:to_s))
    )
  end
end
