# Decide e dispara os alertas de "conversa sem resposta" pra UMA conversa (chamado em lote pelo
# Conversations::UnattendedConversationAlertJob, que já buscou o status do agente antes, em lote,
# pra evitar N+1 no Redis).
#
# 3 camadas independentes, cada uma dispara no maximo 1x por "ciclo de espera" (perido continuo
# em que conversation.waiting_since fica preenchido, do jeito que o Chatwoot ja rastreia
# nativamente):
#   - Camada 3: agente responsavel esta ausente/offline enquanto tem mensagem sem resposta —
#     avisa o CLIENTE que o atendente se ausentou. Mais rapida (limiar menor) e mais precisa.
#   - Camada 1: agente esta online mas demorou — avisa o CLIENTE que a equipe ja viu.
#   - Camada 2: independente do motivo, demora passou de um limite maior — avisa os
#     ADMINISTRADORES (nota interna + notificacao), sem reatribuir nada automaticamente.
#
# Camadas 1 e 3 sao mutuamente exclusivas em UMA mesma checagem (dependem do status atual do
# agente, que so pode ser um), mas podem disparar as duas ao longo do MESMO ciclo se o status do
# agente mudar entre checagens (ex: estava away, camada 3 disparou; agente fica online sem
# responder, camada 1 dispara depois) — isso e intencional, cada uma e uma informacao nova.
class Conversations::UnattendedAlertService
  LAYER3_AWAY_MINUTES = ENV.fetch('UNATTENDED_ALERT_LAYER3_MINUTES', 5).to_i
  LAYER1_DELAY_MINUTES = ENV.fetch('UNATTENDED_ALERT_LAYER1_MINUTES', 10).to_i
  LAYER2_ESCALATE_MINUTES = ENV.fetch('UNATTENDED_ALERT_LAYER2_MINUTES', 30).to_i

  LAYER3_MESSAGE = 'Seu atendente se ausentou por um instante — já já alguém dá continuidade ' \
                   'ao seu atendimento. Obrigado pela paciência! 🙏'.freeze
  LAYER1_MESSAGE = 'Ainda estamos com você! Nossa equipe já viu sua mensagem e vai responder ' \
                   'em breve. 🙏'.freeze

  pattr_initialize [:conversation!, :agent_status!]

  def perform
    return if waited_minutes.nil?

    try_layer(3) if layer3_due?
    try_layer(1) if layer1_due?
    try_layer(2) if layer2_due?

    persist_layers_sent if @layers_sent_changed
  end

  private

  def agent_away?
    agent_status != 'online'
  end

  def layer3_due?
    agent_away? && waited_minutes >= LAYER3_AWAY_MINUTES
  end

  def layer1_due?
    !agent_away? && waited_minutes >= LAYER1_DELAY_MINUTES
  end

  def layer2_due?
    waited_minutes >= LAYER2_ESCALATE_MINUTES
  end

  # Memoizado — chamado varias vezes por perform (guarda + cada layerN_due?), todos precisam ver
  # o mesmo instante "agora", nao um recalculo levemente diferente a cada chamada.
  def waited_minutes
    return @waited_minutes if defined?(@waited_minutes)

    @waited_minutes = conversation.waiting_since.present? ? (Time.current - conversation.waiting_since) / 60 : nil
  end

  def try_layer(layer)
    return if layers_sent.include?(layer)

    case layer
    when 1 then send_customer_message(LAYER1_MESSAGE)
    when 3 then send_customer_message(LAYER3_MESSAGE)
    when 2 then escalate_to_administrators
    end

    layers_sent << layer
    @layers_sent_changed = true
  end

  def send_customer_message(content)
    Messages::MessageBuilder.new(nil, conversation, { content: content, private: false }).perform
  end

  # Sem tipo de notificacao proprio de proposito: criar um novo `notification_type` custom
  # exigiria adicionar rotulo de preferencia de notificacao em quase 60 arquivos de i18n pra um
  # alerta interno estreito — reaproveita `assigned_conversation_new_message` (ja tem push/email
  # funcionando) e conta com a nota privada abaixo pra dar o contexto real do motivo.
  def escalate_to_administrators
    note = "⚠️ Conversa aguardando resposta há mais de #{LAYER2_ESCALATE_MINUTES} min sem " \
           'retorno do agente responsável.'
    Messages::MessageBuilder.new(nil, conversation, { content: note, private: true }).perform

    notify_users.each do |user|
      NotificationBuilder.new(
        notification_type: :assigned_conversation_new_message,
        user: user, account: conversation.account, primary_actor: conversation
      ).perform
    end
  end

  def notify_users
    (conversation.account.administrators.to_a + [conversation.assignee].compact).uniq
  end

  def layers_sent
    @layers_sent ||= begin
      alert = conversation.additional_attributes['unattended_alert'] || {}
      alert['waiting_since'] == conversation.waiting_since.to_s ? Array(alert['layers_sent']) : []
    end
  end

  def persist_layers_sent
    attrs = conversation.additional_attributes || {}
    # update_columns de proposito (mesmo padrao do BotFlow, engine.rb#update_attrs) — e so uma
    # flag interna de controle, nao deve rodar validacoes/callbacks de conversa por causa dela.
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_columns(
      additional_attributes: attrs.merge(
        'unattended_alert' => { 'waiting_since' => conversation.waiting_since.to_s, 'layers_sent' => layers_sent }
      )
    )
    # rubocop:enable Rails/SkipsModelValidations
  end
end
