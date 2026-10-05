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
        agent_status: agent_status_by_id[conversation.assignee_id.to_s] || 'offline',
        # o mapa inteiro vai junto: a camada 2 precisa saber quem, entre os administradores,
        # esta disponivel agora pra nao notificar quem esta com o computador desligado
        available_users: agent_status_by_id
      ).perform
    end
  end

  private

  def candidate_conversations(account)
    # where.not(a: nil, b: nil) geraria "NOT (a IS NULL AND b IS NULL)" (De Morgan), nao o que
    # eu quero — encadear dois where.not separados nega cada condicao individualmente.
    escopo = account.conversations.open
                    .where.not(waiting_since: nil)
                    .where.not(assignee_id: nil)

    isentas = caixas_isentas
    escopo = escopo.where.not(inbox_id: isentas) if isentas.present?

    escopo.limit(Limits::BULK_ACTIONS_LIMIT)
  end

  # Nem toda caixa quer o aviso. Numa caixa de vendas, por exemplo, "seu atendente se ausentou"
  # soa como atendimento falhando onde ainda nem comecou. A lista vive em InstallationConfig
  # (mesmo padrao de INACTIVE_WHATSAPP_NUMBERS), entao mudar nao exige deploy.
  def caixas_isentas
    ids = GlobalConfig.get_value('UNATTENDED_ALERT_EXCLUDED_INBOX_IDS').to_s
    return [] if ids.blank?

    ids.split(',').filter_map { |id| id.strip.presence&.to_i }
  end
end
