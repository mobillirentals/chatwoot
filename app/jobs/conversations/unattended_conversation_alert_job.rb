# Roda a cada 2 min (config/schedule.yml) via Account::UnattendedConversationAlertSchedulerJob.
# Busca as conversas candidatas de UMA conta, pega o status de disponibilidade de todos os
# agentes de uma vez (evita N+1 no Redis) e delega a decisão pra
# Conversations::UnattendedAlertService, conversa por conversa.
class Conversations::UnattendedConversationAlertJob < ApplicationJob
  queue_as :low

  def perform(account:)
    conversations = candidate_conversations(account)
    return if conversations.blank?

    agent_status_by_id = OnlineStatusTracker.get_available_users(account.id)

    conversations.each do |conversation|
      Conversations::UnattendedAlertService.new(
        conversation: conversation,
        agent_status: agent_status_by_id[conversation.assignee_id.to_s] || 'offline'
      ).perform
    end
  end

  private

  def candidate_conversations(account)
    # where.not(a: nil, b: nil) geraria "NOT (a IS NULL AND b IS NULL)" (De Morgan), nao o que
    # eu quero — encadear dois where.not separados nega cada condicao individualmente.
    account.conversations.open
           .where.not(waiting_since: nil)
           .where.not(assignee_id: nil)
           .limit(Limits::BULK_ACTIONS_LIMIT)
  end
end
