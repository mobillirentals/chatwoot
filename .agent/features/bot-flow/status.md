# BotFlow (bot de triagem WhatsApp) — Status

> Bot de triagem **EM PRODUÇÃO** desde 14/07/2026 (voltou depois de um dia com o Captain rodando — decisão de negócio, não bug; ver `.ai/features/captain/status.md`). Typebot descontinuado, o BotFlow é uma máquina de estados em Ruby puro.

## Arquivos-chave

- `app/services/bot_flow/engine.rb` — máquina de estados: `start · triagem_inicial · menu · financeiro · atendimento (→ veículo/documentos/ouvidoria) · emergencia_menu (→ roubo/furto | socorro) · atendente · despedida`
- `app/services/bot_flow/bridge_service.rb` — webhook bridge: dedup por `last_processed_message_id`, detecção de pin de localização, delivery com ordenação (`sleep 0.4` entre msgs)
- `app/services/crm/client_profile_service.rb` — CRM Bitrix+Asaas, `detect_charge_type` (multa/parcela/cobrança) por texto livre na descrição

## Gotchas de plataforma

- Negrito WhatsApp = `**x**` (nunca `*x*` isolado → vira itálico via CommonMarker).
- Título de botão ≤ 20 caracteres (limite WhatsApp Cloud API); lista ≤ 24.
- **⚠️ O toque num botão de resposta rápida volta pro bot como o TÍTULO visível, não o `value`
  interno de `{ title:, value: }`** (confirmado em produção, 01/09/2026 — ver linha do tempo). Até
  então nunca tinha dado problema porque todo `title`/`value` de todo botão do bot sempre foram
  escolhidos parecidos o suficiente pra `normalize`+`match_any` (substring) casar com QUALQUER um
  dos dois. Um `match_any(...)` que dependa só do `value` sem também cobrir o texto real do
  título vai silenciosamente nunca disparar no toque do botão (só funciona se o cliente digitar
  à mão). Sempre incluir o texto normalizado do `title` no `match_any(...)`.
- Emergência com submenu: Roubo/Furto → time `monitoramento e sinistros` (pede B.O.); Socorro → pede localização → time `socorro`.
- Handoff usa `conversation.update!(status: :open, team_id:, ai_assignee: nil)` — `update_columns` não serve, porque é o callback que faz o round-robin, a atividade e o broadcast. ⚠️ **O `ai_assignee: nil` não é detalhe**: sem ele o Chatwoot não escolhe agente nenhum (ver 02/10/2026 na linha do tempo).
- Times reais na VM: `financeiro`(4) · `manutenção`(6) · `documentação e multas`(5) · `pós-venda`(1) · `ouvidoria`(7) · `socorro`(3) · `monitoramento e sinistros`(2) · `suporte app`(8).

## Linha do tempo

**08/07/2026 — Redesenho do fluxo.** Namespace migrado `typebot/` → `bot_flow/`. Rota `webhooks/typebot` mantida por compatibilidade, aponta pro `Webhooks::BotFlowController`.

**14/07/2026 — PRs #54/#55, no dia em que voltou a ser o bot ativo:**
- **PR #54**: saudação (`handle_start`) bloqueava esperando Bitrix+Asaas antes de dizer "Olá" (~3s). Corrigido: saudação imediata (~0,07s) com `contact_first_name` (nome do WhatsApp, não o do CRM em CAIXA ALTA); CRM aquecido em background (`BotFlow::CrmWarmupJob`) só quando o cliente chegasse no Financeiro. Removida a prévia de valor/tipo de cobrança na entrada do Financeiro (mesmo problema do `detect_charge_type` visto no Captain).
- **PR #55**, mesmo dia: removido o autoatendimento de pagamento por completo — não só a prévia, o botão "Quero o link" inteiro. Financeiro ficou só com "Atendente"; texto livre tipo "quero o link"/"pagar"/"fatura" transfere direto. Isso deixou o CRM **sem consumidor nenhum** no BotFlow — `BotFlow::CrmLookup` e `BotFlow::CrmWarmupJob` (criados na #54) removidos no mesmo dia. `Crm::ClientProfileService` continua vivo por fora, via `Webhooks::CrmController`.

**Efeito colateral (14/07):** durante os testes, a inbox **Bot Lab foi apagada sem querer** numa limpeza do usuário e precisou ser recriada — mudou de id 2 para id 3.

**04/08/2026 — PR #69: bot respondia por cima de agente que já tinha a conversa atribuída.** Achado na conversa #271: agente manda template + se auto-atribui antes do cliente responder; quando o cliente responde, o `AgentBotListener` nativo dispara o bot mesmo assim (só olha se a inbox tem bot ativo, não se já tem dono humano). Como a conversa nunca passou pelo fluxo do bot, não tem `bot_state` salvo, cai em `'start'` e roda a saudação/menu inteiros. A proteção existente (`bot_state == 'atendente'`) só cobre handoff feito pelo próprio bot. Corrigido com guard cedo em `BridgeService#perform` (`human_assigned?` — `assignee_id.present?`). Não interfere no handoff nativo do bot (nesse caminho `bot_state` já vira `atendente` no mesmo passo que o round-robin preenche `assignee_id`). **Confirmado em produção pelo usuário no mesmo dia** (conversa #338: template + auto-atribuição, cliente respondeu, bot ficou em silêncio — reproduz exatamente o teste local).

**04/08/2026 — PR #76: mesma raiz da PR #69, sintoma diferente — conversa iniciada por agente ficava presa em `pending` pra sempre.** Achado investigando por que o time financeiro tinha várias conversas `pending` com histórico normal de mensagens (ex.: #340). Toda conversa nova nesta inbox nasce `pending` (bot ativo, nativo); só o handoff do próprio bot (`Engine#hand_off_to_human`) marca `open`. Uma conversa iniciada pelo agente (template + auto-atribuição, sem o cliente ter falado com o bot) nunca passa por esse handoff — fica `pending` pra sempre, mesmo com vaivém normal depois. Corrigido no mesmo guard da PR #69 (`human_owns_conversation?`, ex-`human_assigned?`): se a conversa ainda está `pending` quando o guard silencia o bot, abre ela na resposta do cliente. Validado só localmente (sem confirmação do usuário em produção ainda) — sem suíte de specs pra essa área, mesmo padrão de verificação das PRs #67-#69.

**01/09/2026 — Atalho por palavra-chave pra migração da plataforma de cobranças (Moto Fácil).**
Contexto: empresa migrando o painel de cobranças pro "Moto Fácil" (motofacil.club), time novo
`suporte app` (id 8) criado só pra isso. Botão "Solicite pelo WhatsApp" no app antigo (redirect de
`painel.mobillirentals.com.br`) configurado pra abrir o WhatsApp com o texto pré-preenchido **"Olá,
preciso de ajuda para acessar o Moto Fácil"**. Como o BotFlow não tinha nenhum reconhecimento de
palavra-chave em texto livre (só menu numerado/botão), adicionado um atalho global em `process`
(mesmo padrão do `back_command?` já existente): se a mensagem contém "moto facil"/"motofacil"
(normalizado — funciona com ou sem espaço, cobre `motofacil.club` também), transfere direto pro
time `suporte app`, pulando o menu inteiro — inclusive funciona vindo de `start` (é exatamente o
caso do clique no botão do app antigo). Único estado excluído: `atendente` (não interrompe
atendimento humano já em andamento). Testado localmente (`rails runner`): mensagem exata do botão,
variante com "motofacil.club" em texto livre no meio do fluxo, fluxo normal (financeiro) sem
interferência, e não-disparo quando já em atendimento humano — todos corretos.

**01/09/2026 — Pergunta de triagem logo na saudação, pra pegar quem nem sabe mencionar "Moto
Fácil".** Complementa o atalho por palavra-chave acima: aquele só ajuda quem clica no botão certo
ou digita o nome da plataforma; a maioria vai chegar sem mencionar nada. WhatsApp limita a 3 botões
por mensagem e o menu principal já usa os 3 (Financeiro/Atendimento/Emergência), então não dava pra
só acrescentar um 4º botão ali — em vez disso, novo estado `triagem_inicial` intercala ANTES do
menu: a saudação já vem com um aviso curto da migração e 2 botões (📱 Moto Fácil / 🎧 Atendimento).
"Moto Fácil" nesse novo estado é resolvido pelo mesmo atalho global de `process` (nem precisa de
`when` próprio); só "Atendimento normal" tem handler dedicado (`handle_triagem_inicial`), que leva
pro menu de sempre. Controlado por `MOTOFACIL_ANNOUNCEMENT_ENABLED` (ENV
`BOTFLOW_MOTOFACIL_ANNOUNCEMENT`, default true) — pra desligar quando a migração estabilizar sem
precisar de outro deploy de código, só variável de ambiente + restart. Testado localmente: saudação
vem com o aviso certo, botão Moto Fácil transfere direto, "atendimento normal" cai no menu de
sempre e o resto do fluxo (ex: financeiro) continua igual, input inválido re-pergunta com os mesmos
2 botões.

**01/09/2026, mesmo dia — 2 correções depois do primeiro teste real em produção:**
1. **Nome "Moto Fácil" removido do botão/aviso**, a pedido do usuário — generalizado pra "nova
   plataforma" (não deixar o cliente precisar reconhecer o nome da marca pra escolher a opção).
2. **Bug real encontrado no teste em produção**: o botão "Ajuda plataforma" não transferia pro
   time, ficava re-perguntando em loop ("Por favor, escolha uma das opções"). Causa: o toque no
   botão volta pro bot com o **título visível**, não o `value` interno — eu tinha só trocado o
   `title` (de "Moto Fácil" pra "Ajuda plataforma") mas deixado o `value` como `'moto facil'`,
   achando que era isso que voltava. Como "ajuda plataforma" não batia mais com o atalho global
   nem com nenhum `match_any` de `handle_triagem_inicial`, caía sempre no `else`. Corrigido com
   match explícito no próprio `handle_triagem_inicial` pro texto real do título ("ajuda
   plataforma"), sem depender do atalho global — ver gotcha de plataforma acima (nunca tinha
   aparecido antes porque todo botão anterior tinha title/value parecidos o bastante pra funcionar
   por acidente). Testado localmente reproduzindo o texto exato que o WhatsApp manda de volta. O
   commit desse fix foi pushado numa branch cuja PR (#94) já tinha sido mesclada nesse meio tempo —
   ficou órfão, resgatado com `cherry-pick` na PR #95 (mergeada, ver gotcha de commit órfão em
   `conversation-export-pdf/status.md` — mesmo padrão, sempre conferir `gh pr view` antes de
   empurrar mais commits numa branch de PR já aberta).

**Confirmado pelo usuário em produção (01/09/2026), depois da PR #95**: fluxo completo funcionando
de ponta a ponta — link `wa.me` do painel antigo (`painel.mobillirentals.com.br`, texto
pré-preenchido "Olá, preciso de ajuda para acessar o Moto Fácil") chega no bot, aviso da migração
aparece, botão "Ajuda plataforma" transfere corretamente pro time `suporte app`. Usuário replicando
o mesmo botão de acesso direto no app mobile também (fora do escopo deste fork).

**24/09/2026 — "📅 Agendar revisão" passou a transferir direto pro time (PR #100).** Pedido da
oficina (print da Yasmin no grupo): o link `https://mobillirentals.com.br/agendamento` que o bot
mandava **não abre o booking** — cai na home do site, sem contexto — e a equipe prefere marcar pelo
WhatsApp mesmo ("eu agendo por aqui, até melhor pra gente controlar"). O botão continua no submenu
Veículo/Oficina (é ele que diz ao time o que o cliente quer), mas agora chama `transfer_to('manutenção', …)`
em vez de responder com o link. Saíram do código a constante `AGENDAMENTO_URL` e o
`agendamento_message`, que ficaram sem uso — mesmo padrão da PR #55, quando o autoatendimento de
pagamento saiu e o Financeiro ficou só com transferência. **Não testado localmente** (a mudança é
uma linha que espelha a opção vizinha "Atendente", já em produção) e **não deployado**: a infra da
Azure está fora por fatura em aberto, então o merge tem que esperar a VM voltar.

**02/10/2026 — O bot transferia o time mas ninguém era atribuído (PR #116).** Reclamação do
atendimento, que vinha transferindo na mão: conversa entregue pelo bot parava na fila do time sem
agente, **mesmo com agente do time online**.

Não era configuração. Na conversa #72833, conferido em produção: caixa com atribuição automática
ligada, time `pós-venda` com `allow_auto_assign`, a única integrante online e membro da caixa. E o
próprio cálculo do Chatwoot (`conversation.send(:find_assignee_from_team)`, que não salva nada)
respondia o nome dela — o sistema sabia para quem mandar.

**Causa: o bot continuava sendo o responsável pela conversa** (`ai_assignee_type = 'AgentBot'`), e o
Chatwoot não procura agente quando já existe um. Dois caminhos, fechados pelo mesmo motivo:

- `AssignmentHandler#ensure_assignee_is_from_team` → `return if ai_assignee_type.present?`, antes do
  `self.assignee ||= find_assignee_from_team`;
- `AutoAssignmentHandler#should_run_auto_assignment?` → `return false if assignee_agent_bot_id.present?`.

Faz sentido para o Chatwoot ("já tem responsável, não mexe"), só que no handoff o bot está
justamente **saindo** da conversa — e ele nunca largava. A correção é soltar o `ai_assignee` no mesmo
save que entrega o time, igual ao que o Chatwoot já faz quando um humano abre a conversa
(`ConversationsController#handle_human_open`).

⚠️ **Vinha de longe e ninguém tinha notado**: a conversa parada mais antiga era de **06/08/2026**, e
no dia do achado havia **13 conversas abertas** nessa situação (financeiro 6, manutenção 3,
pós-venda 2, ouvidoria 2). O deploy **não corrige o passado** — essas precisam ser atribuídas à
parte, e ficaram esperando decisão do usuário.

**Primeiro spec do BotFlow** nasceu aqui (`spec/services/bot_flow/engine_spec.rb`, 5 exemplos).
💡 **Duas armadilhas do cenário, que quase deixaram o teste inútil:**

1. A conversa precisa nascer **`pending`**, como no fluxo real em que o bot atende. Criada já
   `open`, o rodízio atribui alguém na própria criação e o teste passa sem exercitar nada — foi o
   que aconteceu na primeira versão, que passava com e sem a correção.
2. A presença do agente precisa de stub (`OnlineStatusTracker.get_available_users`): o rodízio só
   sorteia entre quem está online, e isso vive no Redis.

Regra que fica: **ao escrever teste de regressão, rodar uma vez sem a correção.** Se passar, o teste
não está testando o que se pensa.
