# Aviso de Inatividade do Cliente + Auto-Resolve — Status

> **⏸️ EM STANDBY** — só discussão de design, nada implementado. Retomar quando o usuário decidir
> os limiares (X/Y) e o texto das mensagens (ver "Pendente pro usuário" abaixo).

## Ideia

Espelho do [[unattended-conversation-alert]], mas do lado do CLIENTE em vez do agente: agente já
respondeu (`waiting_since IS NULL`), cliente some — depois de X tempo, manda um aviso pro cliente
("ainda por aí?"); depois de mais Y tempo sem resposta, fecha a conversa automaticamente.

## O que já existe nativo no Chatwoot (não reinventar)

Configurações → Fluxo de Conversa → **Auto Resolve** já existe, mas está **desligado** nesta conta
(`Account#auto_resolve_after: nil`). O que ele faz:

- `Account#auto_resolve_after` (minutos), `#auto_resolve_message` (texto opcional de despedida),
  `#auto_resolve_ignore_waiting` (bool), `#auto_resolve_label` — tudo em `settings` (jsonb),
  configurável via UI (`AutoResolve.vue`).
- `Conversations::ResolutionJob` (fan-out por conta via `Account::ConversationsResolutionSchedulerJob`,
  parte do hub `TriggerScheduledItemsJob` a cada 5 min) resolve conversas via
  `Conversation.resolvable_not_waiting(auto_resolve_after)` (só quando `waiting_since IS NULL` —
  agente já respondeu, cliente que sumiu) ou `.resolvable_all` (ignora quem deve resposta, mais
  agressivo) dependendo de `auto_resolve_ignore_waiting`.
- `MessageTemplates::Template::AutoResolve` já trata a janela de 24h do WhatsApp direito: se
  `conversation.can_reply?` for false, não tenta mandar a mensagem de despedida — em vez disso cria
  uma mensagem de **atividade** (nota interna) avisando "não enviado por causa da janela de
  mensagem". Padrão melhor que o que eu fiz na primeira versão do alerta de agente (lição já
  aprendida, ver [[unattended-conversation-alert]] bug #1 — vale seguir esse exemplo nativo desta
  vez em vez de reinventar).

**Gap**: é um mecanismo de UM estágio só — a mensagem de despedida e o fechamento acontecem juntos,
no mesmo limiar. Não existe "avisa em X, fecha em X+Y" nativamente.

## Direção proposta (não implementada)

Não reconstruir o "fechar" — reaproveitar o nativo pra isso:

1. Ligar o Auto Resolve nativo com `auto_resolve_after = X+Y` (o limiar TOTAL, contado desde
   `last_activity_at`), `auto_resolve_message` = texto de despedida, `auto_resolve_ignore_waiting =
   false` (nunca fechar em cima de uma resposta que a gente ainda deve).
2. Construir só a peça que falta: um job novo e pequeno (mesma arquitetura do
   [[unattended-conversation-alert]] — service + job + scheduler + entrada em `schedule.yml`),
   disparando UMA VEZ em X minutos de inatividade, usando a MESMA condição do nativo
   (`waiting_since IS NULL` + `last_activity_at` velho) só que com o limiar menor. Aplicar desde o
   início as lições já aprendidas: `conversation.can_reply?` antes de mandar (fallback pra nota de
   atividade, como o nativo já faz) e `inbox.out_of_office?` antes de avaliar.

## Pendente pro usuário (bloqueando o início da implementação)

1. **Valores de X (aviso) e Y (tempo extra até fechar)** — nenhum valor decidido ainda. Opções
   discutidas informalmente: curto (4h/+20h = 24h total), médio (24h/+24h = 48h total), longo
   (48h/+48h = 96h total), ou um valor customizado.
2. **Texto das duas mensagens** (aviso de inatividade pro cliente + despedida ao fechar) — usuário
   ainda não decidiu se escreve ele mesmo ou se eu rascunho no mesmo tom das mensagens do
   [[unattended-conversation-alert]].

Retomar perguntando isso antes de qualquer código.

## ⚠️ 02/10/2026 — Levantamento antes da limpeza, e uma armadilha

Medido na caixa **Whatsapp Mobilli Prod** (inbox 5), conta 1:

| situação | quantidade |
|---|---|
| em atendimento (`open`) | 36 |
| com o bot (`pending`) | **5.596** |
| └ parado há mais de 30 dias | 3.310 |
| └ entre 7 e 30 dias | 1.842 |
| └ entre 24h e 7 dias | 347 |
| └ nas últimas 24h | 97 |

Tudo a partir de **03/08/2026** — a data em que o BotFlow passou a deixar a conversa em `pending`.
Nenhuma foi resolvida desde então: o bot abre, o cliente some no meio do menu e ninguém fecha.

🔴 **A armadilha: o CSAT está LIGADO na caixa** (`csat_survey_enabled: true`). Resolver conversa
dispara o `CsatSurveyListener` → `CsatSurveyService`, que manda pesquisa de satisfação ao cliente.
Resolver as 5.596 de uma vez mandaria pesquisa para gente que falou com a empresa meses atrás.

O que segura o estrago hoje é **sorte, não desenho**: o template de CSAT da caixa
(`customer_satisfaction_survey_5_1`) está com status **PENDING** na Meta, e template não aprovado
não pode ser enviado — então o serviço cai na regra da janela de 24h e, fora dela, só registra
"não enviado". **No dia em que a Meta aprovar esse template, isso muda sozinho**: resolver conversa
antiga passa a disparar template de verdade, que fura a janela de 24h e é cobrado por envio.

Consequência para esta feature: **o auto-resolve nativo não pode ser ligado sem decidir o CSAT
antes**. Com o template aprovado, cada fechamento automático vira uma pesquisa paga para alguém que
sumiu — exatamente quem menos tende a responder.

Formas de resolver em massa sem disparar nada (para a limpeza pontual, não para a feature):
`update_columns(status: :resolved)` pula os callbacks — sem CSAT, sem webhook e sem evento de
relatório, o que para conversa de bot abandonada é desejável: evita inflar as métricas com milhares
de "resoluções" que nenhum atendente fez.

**Decisão pendente do usuário** (02/10/2026): corte da limpeza (sugerido: parado há mais de 7 dias,
5.152 conversas, preservando as 444 recentes) e se resolve com ou sem rastro. O usuário avisou que
quer propor uma implementação nova antes da limpeza.
