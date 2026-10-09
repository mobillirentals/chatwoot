# Alerta de Conversa Sem Resposta — Status

> **Completo e estável, em produção.** PRs #88–#92 mergeadas/deployadas/confirmadas (26–27/08/2026).
> 3 camadas de alerta automático quando o agente responsável não responde uma conversa aberta.
> 5 achados reais de produção corrigidos no primeiro dia e meio (ver seções abaixo) — nenhuma
> pendência conhecida no momento, só acompanhamento contínuo com casos reais.

## Contexto

Cenário levantado pelo usuário: atendente numa conversa sai (almoço/ausência), cliente manda
mensagem nesse meio tempo — antes disso, nada acontecia. Confirmado no banco de produção: zero
Políticas de SLA e zero Regras de Automação ativas na conta. Confirmado no código-fonte que a
engine nativa de Automação **não dá conta disso**: não existe evento de mudança de
`availability_status` disparado em lugar nenhum de `lib/events/types.rb`, e a "ausência automática
por inatividade" nem tem hook (calculada preguiçosamente via TTL no Redis). Por isso, código
customizado, no mesmo espírito do [[bot-flow]].

## Desenho (3 camadas)

- **Camada 3** (mais rápida/precisa, limiar padrão 5 min): agente responsável ausente/offline
  **e** mensagem do cliente sem resposta → avisa o **cliente** que o atendente se ausentou.
- **Camada 1** (fallback, limiar padrão 10 min): agente online mas demorou → avisa o **cliente**
  que a equipe já viu e vai responder.
- **Camada 2** (escalonamento, limiar padrão 30 min): independente do motivo → nota interna na
  conversa + notificação pros **administradores** (+ o próprio assignee). Sem reatribuição
  automática — decisão explícita do usuário, pra não repetir problema de handoff confuso já visto
  neste fork.
- Camadas 1 e 3 são mutuamente exclusivas **numa mesma checagem** (dependem do status atual do
  agente, só pode ser um), mas podem disparar as duas ao longo do **mesmo ciclo de espera** se o
  status do agente mudar entre checagens — intencional, cada uma é informação nova pro cliente.
- Dedup por ciclo: flag `additional_attributes['unattended_alert'] = {waiting_since, layers_sent}`
  por conversa (mesmo padrão do BotFlow, `engine.rb#save_state`) — muda `waiting_since` (ciclo novo,
  agente respondeu e cliente mandou mensagem de novo) reseta a flag automaticamente.

## Arquivos-chave

- `app/services/conversations/unattended_alert_service.rb` — lógica de decisão por conversa
  (camadas, limiares, dedup, disparo de mensagem/nota/notificação).
- `app/jobs/conversations/unattended_conversation_alert_job.rb` — por conta: busca conversas
  candidatas (`open`, `waiting_since` e `assignee_id` preenchidos), pega status de disponibilidade
  de todos os agentes de uma vez (`OnlineStatusTracker.get_available_users`, evita N+1 no Redis),
  chama o service conversa por conversa.
- `app/jobs/account/unattended_conversation_alert_scheduler_job.rb` — fan-out por conta (padrão
  igual aos outros hubs de `config/schedule.yml`).
- `config/schedule.yml` — nova entrada, cron a cada 2 min (mais frequente que o hub genérico de
  5 min, porque a Camada 3 promete reação rápida — limiar padrão de 5 min).

## Peças nativas reaproveitadas (sem reinventar nada)

- `Conversation#waiting_since` — já existe, já é setada/limpa automaticamente pelo Chatwoot
  nativo exatamente no sentido "esperando resposta do agente".
- `OnlineStatusTracker.get_available_users(account_id)` — só reporta agentes com presença Redis
  **ativa** (TTL de 20s simulando conexão WebSocket real), não só `availability` no banco. Um
  agente sem presença simulada aparece ausente do hash → o job já trata isso corretamente como
  `'offline'` (fallback), que é semanticamente certo pro propósito aqui (sem conexão ativa = não
  consegue responder agora).
- `Messages::MessageBuilder.new(nil, conversation, params)` — `nil` no lugar do usuário = mensagem
  de sistema, mesmo mecanismo de uma resposta manual de agente. Confirmado em teste manual que
  dispara o fluxo normal de mensagem pública.
- `NotificationBuilder` — reaproveita o tipo `assigned_conversation_new_message` já existente (tem
  push/email funcionando) em vez de criar um `notification_type` novo, que exigiria rótulo de
  preferência de notificação em ~60 arquivos de i18n pra um alerta interno estreito. A nota privada
  que acompanha dá o contexto real do motivo.
- "Quem é o supervisor": não existe papel de supervisor no Chatwoot — seguido o precedente do
  próprio SLA nativo (`enterprise/app/models/sla_event.rb#create_notifications`): notifica
  `account.administrators` + o assignee da conversa.

## Configuração

Limiares via ENV (sem UI de configuração — fora do escopo por decisão do usuário, pode expor
depois se fizer sentido):
- `UNATTENDED_ALERT_LAYER3_MINUTES` (padrão 5)
- `UNATTENDED_ALERT_LAYER1_MINUTES` (padrão 10)
- `UNATTENDED_ALERT_LAYER2_MINUTES` (padrão 30)

## Verificação (26/08/2026, via `rails runner` em dev, dados de teste limpos ao final)

- ✅ Camada 3 dispara com agente `busy` e 6 min de espera; conteúdo correto.
- ✅ Rodar de novo imediatamente **não duplica** a mensagem (dedup funcionando).
- ✅ Camada 2 dispara com 31 min de espera: nota privada criada + notificação chega pros admins.
- ✅ Ciclo novo (`waiting_since` muda) reseta a flag e permite alertar de novo normalmente.
- ✅ Camada 1 dispara (não a 3) com agente genuinamente `online` (presença Redis simulada via
  `OnlineStatusTracker.update_presence`) e 11 min de espera; conteúdo e `layers_sent: [1]`
  corretos.
- ✅ `bundle exec rubocop` nos 3 arquivos Ruby novos: zero ofensas.
- ✅ `spec/configs/schedule_spec.rb`: passa (sem chave duplicada em `schedule.yml`).

## Fora do escopo (de propósito)

- Conversas sem nenhum agente atribuído (`assignee_id IS NULL`) — problema diferente ("ninguém
  pegou"), não o que foi pedido.
- Reatribuição automática — decisão explícita do usuário.
- UI de configuração dos limiares — ENV var é suficiente por enquanto.

## Deploy em produção (26/08/2026) — 2 bugs reais achados no primeiro dia, ambos corrigidos

PR #88 mergeada e deployada no mesmo dia. O usuário acompanhou casos reais em produção e achou 2
problemas que a verificação em dev não cobria (nenhum dos dois testes tinha um canal WhatsApp real
com janela de 24h nem múltiplas checagens no mesmo ciclo):

1. **Mensagem falhava fora da janela de 24h do WhatsApp**: `Messages::MessageBuilder` cria a
   mensagem no Chatwoot normalmente, mas a Meta rejeita o envio de texto livre fora da janela de
   24h desde a última mensagem do cliente — ficava "Falha ao enviar" na conversa (achado numa
   conversa da Marttins). Corrigido reaproveitando `conversation.can_reply?` (mesmo método nativo
   que já pinta o banner "Restrições de janela de mensagem de 24 horas" na UI) — `send_customer_message`
   agora pula o envio se `!can_reply?`, mas a camada ainda é marcada como "tentada" nesse ciclo
   (não fica retentando a cada 2 min). A nota interna da Camada 2 (`layer2_note`) passou a avisar o
   admin quando isso acontece, já que só um template manual chega no cliente nesse caso.
2. **Camada 3 e Camada 1 disparando as duas pro cliente no mesmo ciclo** (achado numa conversa do
   Rafael Lacerda: agente ausente → aviso às 15:58, ficou online sem responder → segundo aviso às
   16:02, 4 min depois). Isso era o comportamento **intencional** desenhado originalmente ("cada
   camada é informação nova"), mas na prática 2 mensagens automáticas em poucos minutos pareceu
   excesso pro usuário ao ver de verdade. Decisão do usuário: no mesmo ciclo, **no máximo 1
   mensagem pro cliente no total** (1 ou 3, a que disparar primeiro) — `try_layer` agora também
   verifica `customer_layer_already_sent?` (`layers_sent.intersect?(CUSTOMER_LAYERS)`) antes de
   mandar qualquer uma das duas. Camada 2 (interna) continua independente, sem essa restrição.

Ambos os fixes verificados via `rails runner` com `ActiveSupport::Testing::TimeHelpers#travel_to`
(necessário pra simular duas checagens do MESMO ciclo em momentos diferentes sem mexer no
`waiting_since` de verdade — mudar esse valor reseta o ciclo por design, então só `travel_to`
consegue simular "o tempo passou" sem disparar esse reset sem querer).

## Bug #3 (26/08/2026, mesmo dia): notificação da Camada 2 chegava como "Sem conteúdo"

Achado numa conversa da Pretto Nuñez: a notificação push/desktop pro admin mostrava só "Sem
conteúdo" em vez do motivo real do alerta. Causa raiz: `Notification#push_message_body`, pro tipo
`assigned_conversation_new_message`, monta o corpo a partir de `secondary_actor`
(`message_body(secondary_actor)` → lê `.content` dele) — e `escalate_to_administrators` nunca
passava esse parâmetro pro `NotificationBuilder`. `NotificationBuilder` cai pra
`secondary_actor || current_user` quando não é passado, e como o job roda em background (sem
`Current.user`), vira `nil` → `message_content(nil)` → `I18n.t('notifications.no_content')` →
"Sem conteúdo".

Corrigido capturando o retorno do `Messages::MessageBuilder` (a própria nota interna que a Camada 2
já cria) e passando como `secondary_actor: note` — a notificação agora mostra o texto real da nota
(truncado em 10 palavras) direto no push/desktop, sem precisar abrir a conversa. Verificado via
`rails runner`: `push_message_body` foi de "Sem conteúdo" pra "⚠️ Conversa aguardando resposta há
mais de 30 min sem...".

## Bug #4 (27/08/2026): alertas disparando fora do horário de atendimento

Achado numa conversa do Rafael de Jesus: mensagem de "fora do horário de atendimento" (nativa do
Chatwoot, Horário de Funcionamento configurado na inbox) disparou às 5:15 da manhã — e a Camada 1
e a Camada 2 dispararam em cima, às 5:26 e 5:46, cobrando resposta de agente e alertando
administradores num horário em que ninguém está escalado pra atender mesmo. Corrigido reaproveitando
`inbox.out_of_office?` (mesmo método nativo do concern `OutOfOffisable` que já decide se mostra a
mensagem automática de fora do horário) — `perform` agora retorna cedo se a inbox estiver fora do
horário, nenhuma das 3 camadas dispara nesse caso. Só afeta inboxes com Horário de Funcionamento
habilitado (`working_hours_enabled`); sem isso configurado, comportamento inalterado.

Verificado via `rails runner`: com a inbox marcada como fechada o dia todo, nenhuma mensagem/nota
é criada mesmo com 40 min de espera (bem acima de todos os limiares); reabrindo o horário, as
camadas voltam a disparar normalmente.

## Fix #5 (27/08/2026): janela de corrida no lote do job

Não achado em produção, levantado numa revisão pedida pelo usuário ("pegamos todos os pontos?").
`Conversations::UnattendedConversationAlertJob#perform` carrega o lote inteiro de conversas
candidatas numa query só, no INÍCIO do método, e só depois itera processando uma por uma. Se um
agente respondesse de verdade a uma conversa ENQUANTO o job ainda estava processando outras do
mesmo lote, o objeto em memória ficava desatualizado — a checagem rodava com `waiting_since` velho
e podia mandar um "ainda estamos com você" pro cliente logo depois de uma resposta real. Corrigido
com `conversation.reload` + re-checagem de `waiting_since`/`assignee_id` no início de cada
iteração, fechando a janela de corrida do tamanho do lote inteiro pra uma única query. Verificado
via `rails runner` simulando o cenário (objeto "stale" em memória + `waiting_since` limpo no banco
por baixo) — sem o reload a checagem prosseguiria com dado velho; com o reload, é pulada
corretamente.

## Pendente

- Confirmação contínua do usuário com mais casos reais em produção.

---

## 29/09/2026 — o alerta interno deixou de acordar quem está fora (PR #109)

Sintoma trazido pelo usuário: ao ligar o computador, chegavam dezenas de notificações de
"Conversa aguardando resposta há mais de 30 min" de uma vez. Causa: a camada 2 notificava
`account.administrators` **inteiro**, sem olhar disponibilidade — e a notificação do Chatwoot é
persistente, então virava push acumulado. A camada 3 já consultava o `OnlineStatusTracker`; a
notificação interna tinha ficado de fora disso por omissão.

Agora entram só os `online` e `busy` (`busy` conta: a pessoa segue na frente do computador). O
mapa de presença que o job já busca uma vez por conta passou a ser repassado ao serviço
(`available_users`), sem consulta nova ao Redis.

**Sem ninguém disponível, nada se perde**: a nota privada continua sendo criada e a conversa segue
na lista de não atendidas. `available_users` nulo mantém o comportamento antigo (avisa todos), para
não mudar o resultado de quem chame o serviço sem informação de presença.

Este PR criou o **primeiro spec do serviço** (5 exemplos). Duas armadilhas de teste que valem para
a próxima vez: `waiting_since` passado na criação da conversa é sobrescrito pelo callback (use
`update_columns` depois), e `let` preguiçoso cria os administradores **depois** da execução, então
`account.administrators` sai vazio — use `let!`.

**Em aberto, por decisão**: trocar "todos os administradores" por um destinatário definido (time de
supervisão) só depois de medir o efeito deste filtro.
