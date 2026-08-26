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
# agente, que so pode ser um). No MESMO ciclo, no maximo UMA mensagem pro cliente é enviada no
# total (1 ou 3, a que disparar primeiro) — testado em producao e confirmado que 2 avisos
# automaticos pro cliente em poucos minutos (ex: agente estava away, camada 3 disparou; virou
# online sem responder, camada 1 disparou 4 min depois) passa impressao de excesso/robo
# insistindo. Camada 2 (interna, pros administradores) continua independente e pode escalar
# depois de qualquer uma das duas.
class Conversations::UnattendedAlertService
  CUSTOMER_LAYERS = [1, 3].freeze

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
    return if CUSTOMER_LAYERS.include?(layer) && customer_layer_already_sent?

    case layer
    when 1 then send_customer_message(LAYER1_MESSAGE)
    when 3 then send_customer_message(LAYER3_MESSAGE)
    when 2 then escalate_to_administrators
    end

    layers_sent << layer
    @layers_sent_changed = true
  end

  def customer_layer_already_sent?
    layers_sent.intersect?(CUSTOMER_LAYERS)
  end

  # Fora da janela de 24h do WhatsApp (`conversation.can_reply?` — mesmo metodo que ja pinta o
  # banner "Restricoes de janela de mensagem de 24 horas" na UI), o envio via API é rejeitado pela
  # Meta: mensagem de texto livre nao chega ao cliente, so fica com "Falha ao enviar" no Chatwoot.
  # Em vez de tentar e falhar (e falhar de novo a cada checagem), pula o envio silenciosamente —
  # a camada ainda e marcada como "tentada" nesse ciclo pelo chamador (try_layer), entao nao fica
  # reprocessando a cada 2 min.
  def customer_reachable?
    return @customer_reachable if defined?(@customer_reachable)

    @customer_reachable = conversation.can_reply?
  end

  def send_customer_message(content)
    return unless customer_reachable?

    Messages::MessageBuilder.new(nil, conversation, { content: content, private: false }).perform
  end

  # Sem tipo de notificacao proprio de proposito: criar um novo `notification_type` custom
  # exigiria adicionar rotulo de preferencia de notificacao em quase 60 arquivos de i18n pra um
  # alerta interno estreito — reaproveita `assigned_conversation_new_message` (ja tem push/email
  # funcionando).
  def escalate_to_administrators
    note = Messages::MessageBuilder.new(nil, conversation, { content: layer2_note, private: true }).perform

    notify_users.each do |user|
      NotificationBuilder.new(
        notification_type: :assigned_conversation_new_message,
        # secondary_actor vira o corpo da notificacao push/desktop (Notification#message_body).
        # Sem isso (nosso job roda em background, sem Current.user) cai em nil e a notificacao
        # chega como "Sem conteudo" — passar a nota que acabamos de criar mostra o motivo real
        # (o texto de layer2_note) direto na notificacao, sem precisar abrir a conversa.
        user: user, account: conversation.account, primary_actor: conversation, secondary_actor: note
      ).perform
    end
  end

  def notify_users
    (conversation.account.administrators.to_a + [conversation.assignee].compact).uniq
  end

  def layer2_note
    base = "⚠️ Conversa aguardando resposta há mais de #{LAYER2_ESCALATE_MINUTES} min sem " \
           'retorno do agente responsável.'
    return base if customer_reachable?

    "#{base} Cliente fora da janela de 24h do WhatsApp — mensagem automática pro cliente não foi " \
      'enviada; só um modelo (template) chega até ele agora.'
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
