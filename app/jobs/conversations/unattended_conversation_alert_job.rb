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
      # O lote inteiro foi carregado no INICIO do metodo (candidate_conversations executa a query
      # e materializa o array aqui) — se um agente responder ENQUANTO esse loop ainda esta
      # processando outras conversas do mesmo lote, o objeto em memoria fica desatualizado.
      # Recarrega bem antes de decidir, pra fechar essa janela (que sem isso ficaria do tamanho
      # do lote inteiro) pro tempo de uma unica query.
      conversation.reload
      next if conversation.waiting_since.blank? || conversation.assignee_id.blank?

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
