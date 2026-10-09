# Captain 100% IA — Caso 1: acesso à plataforma Moto Fácil — Status

> Branch `feat/captain-motofacil-access` (a partir do `deploy/develop`). **Só no ambiente local até agora — nada em produção.**
> Contexto do Captain em geral: `.ai/features/captain/status.md` e `plan.md`.

## Decisão (10/09/2026)

O usuário decidiu abandonar o menu do [[bot-flow]]: o atendimento passa a ser **100% IA (Captain)**, que resolve o que
consegue e transfere para o time certo quando precisa. Começamos pelo caso mais volumoso da análise de dores
(~35% das conversas citam app/acesso/Moto Fácil, migração da plataforma de cobranças).

## Fluxo combinado com o usuário (v2, 10/09/2026)

1. Primeira resposta, sempre: *"O senhor já recebeu as instruções de acesso à plataforma do Moto Fácil e suas credenciais?"*
2. **Não recebeu** → busca o cadastro **pelo telefone de quem está falando** (nunca pergunta o telefone).
3. **Já recebeu** → pergunta qual erro aparece, pede detalhes e **um print da tela**.
   - Tentou as credenciais recebidas e não funcionou → busca o cadastro para gerar uma nova senha (**uma única vez**).
   - Outro problema (site/app com erro, dúvida de uso) → transfere para `suporte app` com o resumo *(ramo não
     especificado pelo usuário; assumido)*.
4. Busca: não achou → avisa e **transfere para `suporte app`**. Achou → confirma o e-mail: *"O e-mail do senhor ainda é o
   xxx@xxx.com?"*. Não é mais → transfere para `suporte app` atualizar.
5. Confirmou → **gera a senha no Moto Fácil** e entrega **pelo WhatsApp**, com o link `https://www.motofacil.club/auth`.
6. Continua sem conseguir depois da senha gerada → não gera de novo, transfere.

v1 → v2: o usuário viu a conversa da 2ª simulação (bot mandou credencial na 1ª mensagem) e pediu a pergunta inicial e o
ramo "já recebeu → diagnosticar antes de gerar". A pergunta inicial é **exigida no servidor**: `motofacil_lookup` recusa
enquanto uma resposta pública do assistente das últimas 24 h não tiver perguntado sobre as credenciais (`credencia` /
`instruç…acesso`) e o cliente não tiver respondido — e a recusa entrega à IA a pergunta exata.

Decisões tomadas nas perguntas: identidade = só o telefone (o usuário não quis confirmação extra por e-mail digitado
ou CPF); senha no WhatsApp (ciente de que fica no histórico, visível aos atendentes).

## Contrato do Moto Fácil (Supabase) — validado contra a API real em 10/09/2026

- Projeto `https://fkftroyyvhdmyyqqligx.supabase.co`. Headers: `apikey` (anon key **pública**, extraída do JS de
  `www.motofacil.club`; conferida: `role=anon`, validade 2035) + `Bearer` de uma sessão de conta admin.
- Login `POST /auth/v1/token?grant_type=password` → 200, sessão de **3600 s** com refresh token.
- Busca `GET /rest/v1/clients?or=(phone.ilike.*<suf9>,whatsapp.ilike.*<suf9>)` → sufixo de 9 dígitos, cai pra 8 se não achar.
- Reset/criação `POST /functions/v1/create-client-access {clientId, email, fullName}` → `success`, `message`
  ("Acesso atualizado com sucesso!" = conta existia), `credentials.{email,password,userId}`, `referralCode`.
- Cliente de teste liberado pelo usuário: **um cliente de teste** (desligado), telefone 27999990002 — pode resetar à vontade.
  A busca volta exatamente 1 cliente (e também existe 1 lead com o mesmo sufixo, já convertido).

## Arquitetura

| Arquivo | Papel |
|---|---|
| `app/services/moto_facil/client.rb` | Cliente HTTP (Faraday). ENV lida **na hora da chamada**; token em Redis (`MOTOFACIL_ACCESS_TOKEN`, TTL = expiração − 2 min); 1 retry em 401 |
| `enterprise/app/services/captain/motofacil_customer_lookup.rb` | Telefone verificado + busca (`found`/`not_found`/`lead_only`/`ambiguous`/`no_email`/`phone_unavailable`/`error`); guarda em Redis o que foi mostrado ao cliente |
| `enterprise/lib/captain/tools/motofacil_lookup_tool.rb` | Ferramenta `motofacil_lookup` — **sem parâmetros** |
| `enterprise/lib/captain/tools/motofacil_generate_access_tool.rb` | Ferramenta `motofacil_generate_access` — **sem parâmetros**, 1 vez por conversa, envia a senha direto ao cliente |
| `enterprise/app/services/captain/conversation/message_history_builder_service.rb` | (upstream, patch pequeno) oculta da IA mensagens marcadas `captain_redact_for_llm` |
| `config/agents/tools.yml`, `lib/redis/redis_keys.rb`, `.env.example` | Registro das ferramentas, chaves Redis, variáveis |
| Transferência | Reaproveita a `assign_team` que já existia (time `suporte app`) |

## Segurança — o que foi decidido e por quê

- **De onde vem o telefone.** Nunca de argumento do modelo (senão "busque o 27999…" acharia outra pessoa) e nunca de
  `contact.phone_number`, que **qualquer atendente edita** no painel — um erro de digitação entregaria a senha de um
  cliente para outro. Vem dos `contact_inboxes` do contato na inbox de WhatsApp: o Chatwoot cria um a partir do `wa_id`
  do webhook da Meta (`Whatsapp::IncomingMessageIdentifierHelper#incoming_message_source_ids`).
- **Armadilha do BSUID (medida em produção, 10/09/2026).** ~49% dos `contact_inboxes` recentes da inbox 5 têm `source_id`
  no formato `BR.1234…` (ID por empresa da Meta, usado quando o cliente adota nome de usuário). Exigir o `source_id` da
  conversa ser numérico travaria metade dos clientes. Mas **todos os 1.051 contatos BSUID também têm um `contact_inbox`
  numérico** na mesma inbox (o `Whatsapp::IdentifierSyncService` cria os dois e nunca substitui). A busca usa esse; se o
  contato tiver 0 ou 2+ telefones, não adivinha (`phone_unavailable` → transfere).
- **Por que não a "custom tool" HTTP nativa do Captain.** Os parâmetros dela são preenchidos pelo modelo e a resposta volta
  pro modelo; o único dado do servidor é o header `X-Chatwoot-Contact-Phone`, tirado do telefone editável.
- **A senha nunca passa pela IA.** A ferramenta cria a mensagem pro cliente e devolve ao modelo só "enviado, não repita".
  Mas **isso sozinho não bastava**: o `MessageHistoryBuilderService` reenvia toda mensagem pública ao modelo a cada turno —
  por isso a mensagem leva `additional_attributes.captain_redact_for_llm` e o builder troca o conteúdo por um placeholder.
- **1 senha por conversa.** Trava Redis `CAPTAIN_MOTOFACIL_ACCESS_LOCK::V1::<conversation_id>` (24 h, `SET NX`). Falha
  antes de a plataforma trocar a senha libera a tentativa; depois de trocar, não.
- **O e-mail confirmado é o e-mail do reset.** Antes de resetar, a busca é refeita; se `client_id`/e-mail mudaram desde a
  confirmação, pede reconfirmação. Se a plataforma devolver credenciais de **outro** e-mail, a senha **não** é enviada e
  fica uma nota interna (o doc do MF cita um caso real de acesso vinculado à conta errada).
- **Nota interna de auditoria** sem a senha. **Credenciais** só em ENV (nunca em código ou doc).

### Riscos que continuam (conhecidos, não resolvidos)

- **Número reciclado:** quem herdar o número de um cliente antigo recebe o acesso dele (identidade = só telefone, decisão do usuário).
- **Senha no histórico do Chatwoot:** visível aos atendentes (aceito). Além disso, outros caminhos de IA que leem a
  conversa — sentimento, resumo do Copilot, geração de FAQ de conversa resolvida — **não passam pelo builder** e podem ler
  a mensagem. Proposta pendente: job que apaga o conteúdo da mensagem de credenciais do Chatwoot alguns minutos depois de
  enviada (continua no celular do cliente).
- **Conta de serviço:** hoje é a conta pessoal `bruno.santos@` — todo reset aparece no MF como feito por ele. Criar uma conta só do bot antes de produção.

## Ambiente local (montado em 10/09/2026)

- `.env` local: `MOTOFACIL_*` + `CAPTAIN_MOTOFACIL_DEV_TRUST_CONTACT_PHONE=true` (o webchat não tem telefone verificado;
  com a flag, fora de produção e fora do WhatsApp, usa o telefone do contato). Chave do Azure colada pelo usuário no
  super admin local (a cópia automática de produção foi bloqueada pelo controle de permissões).
- Conta 47: flags `captain_integration`/`captain_integration_v2`, `captain_models` = `gpt-4.1-mini`, `captain_auto_resolve_mode = disabled`.
- Assistente **"Mobílli"** (#1): 5 guardrails, 4 guidelines; cenário **"Acesso à plataforma Moto Fácil"** (#1) com as
  ferramentas `motofacil_lookup`, `assign_team`, `motofacil_generate_access` resolvidas.
- Inbox **95 "Webchat Teste"**: BotFlow desvinculado, `CaptainInbox` criado.
- Depois de mexer em `tools.yml`/`redis_keys.rb`: **reiniciar `rails` e `sidekiq`** (o catálogo de ferramentas fica memoizado na classe).

## Testes

- Specs: `spec/services/moto_facil/client_spec.rb`, `spec/enterprise/services/captain/motofacil_customer_lookup_spec.rb`,
  `spec/enterprise/lib/captain/tools/motofacil_{lookup,generate_access}_tool_spec.rb`,
  `spec/enterprise/services/captain/conversation/message_history_builder_service_spec.rb`.
- Rodar **com `RAILS_ENV=test` explícito** (o container é `development`): `docker compose exec -T -e RAILS_ENV=test rails bundle exec rspec <arquivos>`.
  O banco de teste é o `chatwoot_test`, mas **o Redis é o mesmo do dev** — não rodar specs no meio de um teste manual.
- 1ª rodada: 33/35; as 2 falhas eram do ambiente (o `.env` local liga a flag de dev e o Rails carrega o `.env` também em
  teste) — spec corrigido pra forçar a flag desligada. Com o spec de gzip (abaixo): **36/36**, Rubocop limpo.
- O `client_spec` grava tokens falsos na chave compartilhada `MOTOFACIL_ACCESS_TOKEN`; ganhou `after` que apaga a chave.
  (Não foi a causa do bug abaixo: na hora, o token guardado era um JWT real.)

### 🐛 Bug achado na simulação de ponta a ponta: resposta gzip

A 1ª simulação (Captain + IA real + API real) terminou em transferência com "plataforma indisponível". Causa: o Supabase
manda as respostas do REST **compactadas em gzip** (`content-encoding: gzip`, corpo começando em `1f 8b`) e o adaptador
`net_http` do Faraday 2.14 entregou os bytes **sem descompactar**, marcados como UTF-8 → `invalid byte sequence in UTF-8`
no `present?`, antes do JSON. O login (POST) veio sem compactação, por isso passava; os specs não pegaram porque os stubs
devolviam JSON puro. Corrigido em `MotoFacil::Client#decoded_body` (descompacta quando o header diz gzip e os bytes
confirmam) + spec com resposta gzip. Confirmado contra a API real pelo Rails: 1 cliente, 1 lead, 0 pra telefone inexistente.
Ponto positivo: a ferramenta capturou a exceção e o bot transferiu em vez de travar — o caminho de falha funcionou.

Outro achado da mesma simulação: o bot chamou a busca já na 1ª mensagem, sem perguntar se o cliente tinha recebido as
credenciais. Passo 1 do cenário reescrito: *"Na primeira resposta, só pergunte se o cliente já recebeu as credenciais ...
e espere a resposta dele. Não chame nenhuma ferramenta antes disso."*

### 🔴 Achado na 2ª simulação: a IA gerou a senha SEM confirmar o e-mail

Com a busca consertada, o `gpt-4.1-mini` respondeu a **primeira** mensagem do cliente ("não consigo acessar") chamando
`motofacil_lookup` e, na mesma resposta, `motofacil_generate_access` — sem perguntar se tinha recebido as credenciais e sem
confirmar o e-mail, apesar do cenário, do passo 1 reescrito e da descrição da ferramenta dizerem o contrário. O resto
funcionou (1 mensagem de credenciais, senha fora do histórico da IA/das falas/da nota, trava ativa, transferência pro
`suporte app` na reclamação sem gerar de novo).

**Lição: instrução não segura regra de segurança — o servidor tem que segurar.** Mudanças:
- `MotofacilCustomerLookup` separado em `#current` (consulta ao vivo, **não grava**) e `#remember` (grava o que foi mostrado
  ao cliente **+ o id da mensagem mais nova naquele momento**, `shown_after_message_id`). Só a ferramenta de busca grava.
- `motofacil_generate_access` só roda se, **depois** dessa marca, uma resposta pública do assistente **contiver o e-mail
  cadastrado** e o cliente tiver mandado **alguma mensagem depois dela**. Se a resposta foi "sim" continua a critério da
  IA; pular a pergunta ficou impossível.
- Fechou uma brecha de quebra: antes, a própria geração regravava o cache com a consulta nova — depois de um "cadastro
  mudou, confirme de novo", a IA podia chamar a geração de novo e passar sem perguntar. Agora só a busca regrava a marca.
- ~~A pergunta "já recebeu as credenciais?" segue só na instrução~~ — virou regra no servidor no fluxo v2 (ver acima).

### 🐛 Achado na 3ª simulação: JSON cru enviado ao cliente

A confirmação obrigatória do e-mail **funcionou** (ferramentas na ordem busca → geração → transferência; senha só depois
de o bot perguntar o e-mail e o cliente responder; 1 mensagem de credenciais; senha fora do histórico da IA, das falas e da
nota; trava ativa). Mas a **primeira fala do bot saiu como texto cru**:
`{"response":"Por favor, confirme se o e-mail…","reasoning":"…"} {"response":"O e-mail do senhor ainda é o …?", …}`.

Causa: a IA tentou gerar o acesso, a ferramenta recusou ("has not confirmed"), e o modelo escreveu **duas respostas
estruturadas na mesma rodada**. O SDK (`ai-agents`) não consegue parsear isso como saída estruturada e devolve a string; o
`Captain::Assistant::AgentRunnerService#process_agent_result` (upstream) colocava a string inteira como resposta — com o
campo interno `reasoning` e tudo. Vai acontecer sempre que uma ferramenta recusar uma chamada, o que o nosso desenho faz de
propósito. Correção (patch pequeno no upstream): `#response_from_text` — se o texto começa com `{`, separa objetos JSON
colados e usa a **última** resposta válida; texto comum segue intacto. Specs novos no `agent_runner_service_spec.rb`.

### ✅ Simulações do fluxo v2 (10/09/2026) — as duas passaram

Rodadas em paralelo, com a IA real, a API real do Moto Fácil e o cliente de teste (webchat com a flag de dev):

| | A — "não recebi" (`+5527999990002`) | B — "recebi, dá senha inválida" (`+552799990002`, **sem o 9º dígito**) |
|---|---|---|
| 1ª fala | pergunta exata sobre instruções/credenciais ✅ | igual ✅ |
| Antes de buscar | — | pediu **o erro, detalhes e print da tela** ✅ |
| Busca | achou (sufixo 9) ✅ | achou pelo **sufixo de 8 dígitos** ✅ |
| Confirmação do e-mail antes da senha | ✅ | ✅ |
| Credenciais | 1 mensagem; senha fora do histórico da IA, das falas e da nota ✅ | igual ✅ |
| Depois | "consegui entrar" → bot agradece, conversa segue `pending` | "ainda não consegui" → **transfere pro `suporte app`** sem gerar de novo ✅ |
| JSON cru | nenhum ✅ | nenhum ✅ |

Ferramentas na ordem: `motofacil_lookup` → `motofacil_generate_access` (→ `assign_team` no B).

Detalhe corrigido depois das duas: o bot disse **"as credenciais foram enviadas ao seu e-mail"** — elas vão **na própria
conversa**. O retorno da ferramenta dizia só "em mensagem separada" e o modelo completou "por e-mail". `SENT` e o passo 5
do cenário agora dizem "nesta conversa, na mensagem acima (não por e-mail)". **Essa redação nova ainda não passou por
simulação.**

Suíte: `agent_runner_service_spec.rb` (upstream, inteiro) + os 5 specs do Moto Fácil = **89 exemplos, 0 falhas**; Rubocop limpo.

### Pontos em aberto levantados pelas simulações

- Depois do "consegui entrar", a conversa fica `pending` com o bot (sem encerrar). Decidir se o Captain encerra
  (`resolve_conversation`) — hoje o auto-resolve está `disabled` no local, o que também bloqueia essa ferramenta.
- No B a transferência caiu no time sem atendente (`Admin` offline) — esperado, fica na fila do `suporte app`.
- Print de tela: a IA do Captain lê imagens do histórico, mas o caso "cliente manda print" ainda não foi testado.

## Caso 2 — negociação, vencimento e parcelamento (10/09/2026)

Regra passada pelo usuário (com duas correções no meio da conversa):
- A Mobílli/Moto Fácil **não negocia**: não troca data de vencimento nem dia de pagamento, não parcela, não divide e
  **não abre exceção**. Vale a data e o valor do sistema; só uma promoção vigente lançada oficialmente muda isso — e o bot
  não tem informação sobre promoções.
- Cliente só pergunta → o bot explica. Insiste ou pede exceção → reforça que não há exceção, **sem transferir**.
- Contesta valor/cobrança, pergunta de promoção/desconto, ou dúvida que o bot não sabe → transfere para **`financeiro`**
  (a primeira versão dizia pós-venda; o usuário corrigiu).
- Dúvida resolvida → "posso ajudar em algo mais?" → "não" → **encerra o atendimento**. Vale para todos os casos (inclui o
  "consegui entrar" do Caso 1, que antes deixava a conversa parada com o bot).
- A regra é só dado (cenário "Negociação, vencimento e parcelamento" + guardrails/guidelines); o encerramento precisou de código.

### Ferramenta `close_conversation` (fork)

- O `resolve_conversation` nativo recusa com `captain_auto_resolve_mode = disabled` (`resolve_conversation_tool.rb:9`), e
  ligar o modo liga o job que varre conversas pendentes a cada hora (o do incidente de julho). O modo segue desligado.
- Encerrar dentro do run engoliria a despedida (o `ResponseBuilderJob` só publica a fala enquanto a conversa está
  `pending`). Mesmo padrão do `assign_team`: a ferramenta marca `captain_resolve_pending` e o
  `Enterprise::Message#complete_captain_team_handoff` → `#finish_deferred_captain_action` resolve logo depois da fala pública
  do assistente. Transferência e encerramento na mesma resposta → **a transferência vence**.
- Adicionada ao roteador (`Captain::Assistant#agent_tools`, arquivo upstream que o fork já tinha alterado para o
  `assign_team`) e referenciada nos dois cenários.
- ⚠️ A inbox de produção tem pesquisa de satisfação (CSAT): o encerramento pelo bot deve disparar a pesquisa, como o
  BotFlow faz hoje — conferir antes de produção.

### Simulações do Caso 2 e do encerramento (10/09/2026)

- **C1 — Caso 1 até o fim** ✅: pergunta inicial → "não recebi" → confirma e-mail → credenciais → bot diz que foram
  enviadas **"aqui mesmo na conversa, na mensagem logo acima"** (a redação nova do `SENT` funcionou; nada de "por e-mail")
  → "consegui entrar" → "posso ajudar em mais alguma coisa?" → "não" → despedida → **conversa encerrada** pelo Mobílli.
  Ferramentas: `motofacil_lookup` → `motofacil_generate_access` → `close_conversation`.
- **N1 — só pergunta se dá pra mudar o pagamento pro sábado** ✅: explicou que não altera vencimento nem dia de pagamento,
  "sem exceções" → "posso ajudar em mais alguma coisa?" → "não" → despedida → **encerrada** (`close_conversation`).
- **N2 — pede exceção, depois contesta o valor** (1ª rodada): não transferiu por causa da exceção ✅, mas **ignorou o
  pedido** e respondeu só "Posso ajudar em mais alguma coisa?" ❌; na contestação transferiu pro **`financeiro`** com nota ✅,
  porém fechou a mensagem da transferência com "posso ajudar em mais alguma coisa?" ❌ (sem sentido com um humano assumindo).
  Ajustes (dado): passo 2 do cenário manda **responder diretamente ao pedido de exceção** e não responder só com outra
  pergunta; passo 3 e as guidelines dizem para **não perguntar "algo mais?" depois de transferir**; o "algo mais?" ficou
  restrito a dúvida resolvida sem transferência; nova guideline "responda ao que o cliente acabou de dizer antes de outra pergunta".
- **N2 — 2ª rodada, com os ajustes** ✅: exceção → *"Senhor, infelizmente não é possível abrir exceção para alteração da
  data de pagamento. Vale a data e o valor que estão no sistema."* (sem transferir) → contestação → transfere pro
  **`financeiro`** com nota e *"Um atendente vai continuar o atendimento com o senhor"*, sem o "algo mais?".
- **N1 — 2ª rodada** ✅: igual à 1ª (sem regressão das guidelines novas) — explica, "algo mais?", "não", encerra.

## Caso 3 — endereços e horários (10/09/2026)

- **Loja da Serra:** R. Euclides da Cunha, nº 111 - Jardim Limoeiro, Serra - ES, 29164-032 — em frente à Yamaha.
- **Loja de Vila Velha:** R. Dr. Jair de Andrade, nº 38 - Itapuã, Vila Velha - ES, 29101-700 — num container da Mobílli,
  em frente à loja da Cibien Motors.
- **Oficina:** R. O, nº 375 - São Geraldo, Serra - ES, 29163-398.
- **Horário das lojas = horário de atendimento configurado na inbox** (o usuário: "já tem configurado na produção, ele pode
  puxar de lá"). Produção, inbox 5, lido em 10/09/2026: seg–sex 08:00–18:00, sáb 08:00–12:00, dom fechado, fuso São Paulo.
  O cenário manda consultar a `business_hours_check`, que lê o horário da inbox na hora — mudar no painel já muda a
  resposta, sem mexer no bot. Local: o script de montagem espelha esse horário na inbox 95.
- **Oficina é a única exceção** ("só esse da oficina que é uma pequena exceção"): seg–sex abre 8h, almoço 12h–13h,
  encerra 17h30. **Sábado (confirmado pelo usuário):** segue o horário das lojas, mas é reservado para tratar casos
  pendentes — **não aceita agendamento**. **Agendamento em dia de semana → `manutenção` (confirmado pelo usuário).**
- Só dado: cenário "Endereços e horários das lojas e da oficina".

## Caso 4 — vendas (10/09/2026)

- O WhatsApp (27) 99775-6598 (inbox "Whatsapp Mobilli Prod") é **exclusivo para clientes**. Vendas: WhatsApp
  **(92) 2398-1266** (`https://wa.me/559223981266`). Se estranharem o DDD 92: a Mobílli tem filial em Manaus.
- O bot não fala preço, plano, disponibilidade nem condição.
- Quem **já é cliente** não recebe o número de vendas. Troca de moto e renovação viraram um cenário próprio (Caso 6, abaixo).
- Só dado: cenário "Vendas: quero alugar uma moto".

## Caso 6 — troca de moto e renovação (10/09/2026, regras do usuário)

- **Troca de moto:** antes de encaminhar, o cliente tem que **explicar bem o motivo** da troca (vago como "quero outra" →
  pedir detalhes); só então transfere para **`pós-venda`**, com o motivo resumido na nota.
- **Renovação: não existe.** Ao terminar a locação atual (desde que não seja por inadimplência), o cliente pode fazer
  **uma nova locação depois**. **Só uma locação por CPF.** O bot explica sem sugerir que o cliente esteja inadimplente e
  sem prometer nova locação, prazo, moto ou condição.
- **Nova locação depois de terminar a atual (confirmado):** pelo WhatsApp de vendas, (92) 2398-1266 — o bot passa o número
  ao explicar a regra. O cenário de vendas só não passa o número para quem quer **trocar de moto**.
- Só dado: cenário "Troca de moto e renovação da locação".

## Caso 7 — moto com defeito, parada ou socorro (11/09/2026, regras do usuário)

Veio da análise das conversas de produção 5925, 7680 e 7661 (nenhum dado de cliente copiado para cá).
- **Bloqueio (risco jurídico):** o bot **nunca** diz que a moto foi, está ou será bloqueada, nem confirma ou nega bloqueio,
  porque o cliente pode usar isso num processo. Se perguntarem, diz que a **equipe especializada de manutenção vai fazer o
  diagnóstico quando a moto estiver em manutenção**. Também não diagnostica a causa. Virou guardrail (vale para todos os
  cenários) e está no cenário.
- **Moto parada:** o bot oferece o **socorro**.
  - Se o cliente aceitar, pede a localização (endereço com referência ou pin do WhatsApp, como o BotFlow já fazia) e
    transfere para o time **`socorro`**, com o problema e a localização na nota.
  - Se recusar, diz que ele pode encaminhar a moto para a oficina para os procedimentos cabíveis.
- **Moto rodando com defeito:** pode levar à oficina. Se quiser agendar na oficina da Mobílli, vai para **`manutenção`**
  (sem agendamento para sábado).
- **Oficina de confiança:** o cliente pode levar a moto numa oficina de confiança dele, se quiser. O bot só confirma quando o
  cliente menciona, e não promete reembolso nem diz quem paga.
- **Pin de localização:** o Captain recebia o pin só como "User has shared an attachment". Patch pequeno no
  `Captain::OpenAiMessageBuilderService` (upstream): a localização vira o texto "User has shared a location: <título> —
  <lat>, <long>" e sai do anexo genérico. +2 specs; builder e histórico somam 22 exemplos, 0 falhas.
- **Trava do socorro (`roadside_assistance_transfer`, nova):** na 1ª rodada, o cliente aceitou o socorro e a IA transferiu
  na hora, sem pedir a localização, **inventando um endereço** na nota ("Rua das Flores, próximo ao supermercado Central").
  - A ferramenta agora recusa se o bot não pediu a localização (fala com "localiza/endereço/onde ... está" nas últimas 24 h)
    ou se o cliente só confirmou ("sim", "ok", "pode mandar").
  - A localização da nota é **copiada das mensagens do cliente** (texto, pin do WhatsApp ou transcrição de áudio), nunca
    escrita pela IA: "Socorro — problema: … | localização enviada pelo cliente: …".
  - A transferência em si é da `AssignTeamTool`. A ferramenta tem 5 specs e entrada no `tools.yml`.
- O cenário "Moto com defeito, parada ou socorro" é dado, em `scripts/local_captain_setup.rb`.
- **1ª rodada (antes da trava, IA real):**
  - socorro com pin ✅: pediu a localização, leu o pin, pôs endereço e coordenadas na nota e transferiu para o `socorro`;
  - recusa do socorro ✅: "pode encaminhar a moto para a oficina para os procedimentos cabíveis", "algo mais?", encerrou;
  - ❌ socorro com endereço por texto: transferiu sem pedir a localização e inventou o endereço;
  - ⚠️ bloqueio: não falou de bloqueio, mas não deu a frase do diagnóstico e perguntou de novo se a moto estava parada;
  - ⚠️ moto rodando: foi para `manutenção`, mas disse "O agendamento foi feito";
  - ❌ oficina de confiança: não respondeu "pode, sim" e transferiu para a manutenção.
- **Ajustes no cenário depois dela:**
  - a frase do diagnóstico vem no começo da resposta;
  - "não liga", "não anda" ou "parou" já contam como moto parada;
  - oficina de confiança recebe "pode, sim", sem transferir;
  - nunca dizer que já está agendado;
  - socorro só pela ferramenta nova.
- **2ª rodada (com a trava, IA real):**
  - socorro com endereço por texto (2 conversas) ✅: a trava recusou o "sim" sozinho, o bot pediu a localização e a nota
    trouxe o endereço **exatamente como o cliente escreveu**;
  - socorro sem localização ✅: não transferiu e seguiu pedindo a localização;
  - socorro com pin ✅: a nota trouxe o endereço e as coordenadas do pin;
  - bloqueio ✅: começou com "a equipe especializada de manutenção fará o diagnóstico…", não citou bloqueio e ofereceu o
    socorro;
  - moto rodando ✅: "vou encaminhar para o time de manutenção fazer o agendamento" → `manutenção`;
  - ❌ oficina de confiança: o orquestrador mandou para o cenário 3 (endereços e horários), que tem "oficina" no gatilho, e
    ele respondeu o horário da oficina. Correção: o cenário 7 passou a cobrir "se pode levar numa oficina de confiança", e o
    cenário 3 diz que não inclui moto com defeito nem oficina de confiança do cliente;
  - ⚠️ pergunta repetida na mesma mensagem em quase todas as respostas.
- **Respostas quase iguais (patch no `AgentRunnerService`, upstream):** quando a IA escreve duas respostas estruturadas numa
  rodada, elas são juntadas, e antes só as idênticas eram descartadas. Agora também sai a resposta cujas palavras (3 letras
  ou mais, sem acento) repetem 60% ou mais de uma anterior. Exemplo: "A moto está parada, correto? Posso acionar o socorro?"
  seguida de "Senhor, a moto está parada. Deseja que eu acione o socorro?". Respostas diferentes continuam juntas. +2 specs
  (54 exemplos somando o spec da ferramenta de socorro, 0 falhas).
- **3ª rodada (roteamento novo e respostas quase iguais):**
  - oficina de confiança (2 conversas) → cenário 7, "pode, sim", "algo mais?", encerrou ✅;
  - bloqueio → frase do diagnóstico e oferta de socorro numa mensagem só ✅;
  - socorro por texto → pediu a localização, e a nota trouxe o endereço real ✅;
  - nenhuma resposta saiu com dois blocos (a pergunta repetida sumiu) ✅;
  - ⚠️ regressão do Caso 3: "quero agendar uma revisão na oficina" foi respondido pelo orquestrador, que perguntou o dia em
    vez de transferir para a `manutenção`. "Revisão" entrou no gatilho do cenário 3.
- **4ª rodada (revisão):** as 2 conversas foram para o cenário 3 ✅.
  - Uma transferiu direto para a `manutenção`, com nota ✅.
  - ⚠️ A outra passou o endereço da oficina e perguntou "Posso ajudar a agendar sua revisão?" em vez de transferir, embora o
    pedido já estivesse claro. É uma pendência menor do Caso 3.

## Caso 8 — multas (11/09/2026, regras do usuário)

- **A cobrança de multa é como qualquer cobrança:** sem alteração de data, parcelamento, desconto ou exceção. O pagamento é
  na plataforma, na parte de cobranças.
- **Multa que não aparece no aplicativo** → **`suporte app`**.
- **Dúvidas detalhadas** (infração, local, notificação, recurso, indicação de condutor) ou contestação da multa →
  **`documentação e multas`**. Contestar multa foi tratado como dúvida detalhada, não como a contestação de valor do Caso 2
  (que vai para o financeiro).
- **Roteamento:** a descrição do assistente manda "multa" para o cenário "Multas", e os cenários 2 e 5 dizem "não inclui multas".
- Só dado: cenário "Multas".
- **1ª rodada (IA real, 6 de 7 certas):**
  - pedido para pagar a multa depois → explicou que não há alteração, perguntou "algo mais?" e encerrou ✅;
  - multa que não aparece → `suporte app` ✅;
  - dúvida sobre infração e local → `documentação e multas` ✅;
  - "posso passar no cartão?" → resposta genérica de pagamento, sem mencionar cartão ✅;
  - regressões: contestação → `financeiro` ✅; diárias → cenário de pagamento ✅;
  - ⚠️ caso misto (multa que "não aparecia antes" mas já aparece): explicou a regra sem transferir. O cenário passou a
    dizer que só vai para o `suporte app` se a multa **ainda** não aparece.
- **2ª rodada:** multa que só demorou a aparecer → explicou a regra, perguntou "algo mais?" e encerrou, sem transferir ✅.

## Decisões de 11/09/2026 que valem para todos os casos

- **Cartão de crédito ou outra facilidade de pagamento:** o bot **nunca** oferece nem menciona. Só um atendente humano
  talvez abra exceção. Virou guardrail.
- **Em aberto, a pedido do usuário:** ouvidoria e reclamações, e os alertas de conversa sem resposta ("estão bem fraquinhos,
  depois pensamos em algo melhor").
- **Achado nas conversas, sem ação ainda:** o menu do BotFlow volta no meio do atendimento depois de uma transferência para
  time sem atendente, porque `BridgeService#human_assigned?` só olha o `assignee_id`.

## Fallback quando a IA cai (11/09/2026, decisão do usuário)

- **Sem menu como atendimento principal:** o agente (Captain) conduz tudo até direcionar para o time. O BotFlow fica só
  como **reserva** para quando a IA cai.
- **Regra escolhida:**
  - Conversa **nova** (o assistente não respondeu nas últimas 24 h) recebe o menu do BotFlow, que faz a triagem e
    transfere para o time.
  - Conversa **em andamento** vai para um atendente, com o histórico, a nota "Assistente virtual indisponível…" e a
    mensagem de transferência do assistente.
  - Fora do horário o menu não roda, então conversa nova também vai para atendente, com o aviso de horário.
  - Quando a IA volta, as conversas novas voltam para ela.
- **Como era antes:** o runner do `ai-agents` não lança o erro da IA; ele devolve o `RunResult` com `error` e sem saída.
  - A resposta vazia quebrava na validação e caía na transferência genérica "Transferindo para que outro agente dê
    assistência.", sem time e sem nova tentativa.
  - Conversa cujo job se perdia ficava pendente para sempre, ou era resolvida sem resposta pelo auto-resolve de 1 h, se
    ele estivesse ligado.
- **Implementação:**
  - `AgentRunnerService`: lê `result.error` e devolve `runner_error` e `ai_outage`. Conta como queda da IA erro de
    provedor ou de rede: 401, 402, 403, 429, 500, 502–504, 529, conexão recusada e timeout.
  - `Captain::Conversation::AiFallbackHandling` (módulo do `ResponseBuilderJob`):
    - na queda da IA, tenta de novo 2 vezes, com 20 s de intervalo;
    - na 3ª falha, marca a IA como indisponível por 5 min no Redis (`CAPTAIN_AI_UNAVAILABLE`) e aplica o fallback;
    - enquanto a marca existe, as conversas pulam a IA, e uma resposta boa limpa a marca;
    - erro só daquela conversa (400, contexto grande, limite de turnos) vai direto para o fallback, sem nova tentativa
      nem marca global.
  - `Captain::Conversation::AiFallbackService`:
    - decide entre menu e atendente;
    - roda o menu pelo `BotFlow::BridgeService`, chamado por dentro com um evento sintético (sem o limite de 10 min) e
      assinado pelo assistente;
    - limpa o `bot_state` antigo, porque conversa que já passou pelo menu tinha `atendente`, que deixa o menu mudo;
    - marca `captain_fallback_bot_flow_at` (vale 6 h) e desmarca quando o menu transfere ou encerra;
    - se o menu ainda assim deixar o cliente sem resposta, passa para atendente.
  - `Captain::UnansweredConversationsFallbackJob` (a cada 2 min): aplica o mesmo fallback a conversa pendente, sem
    atendente, com a última mensagem do cliente sem resposta há entre 5 min e 1 dia.
  - O BotFlow deixa de ser AgentBot na inbox, para não responder junto com o Captain. Na troca em produção, remover o
    `AgentBotInbox` da inbox 5. Com isso some o problema do menu voltando no meio do atendimento.
  - `handoff_message` do assistente: "Um atendente vai continuar o seu atendimento. Só um instante, por favor."
- **Testes:** serviço (10), módulo do job (6), varredura (4) e runner (+1, com os doubles e as expectativas de erro
  ajustados). O spec original do job de resposta, inteiro, segue verde, e o RuboCop está limpo nos arquivos novos. O
  `bridge_service.rb` mantém só as ofensas que já tinha (o hook de pré-commit não bloqueia por lint).
- **Simulação com queda real (IA real, endpoint local apontado para um endereço inacessível e depois restaurado):**
  - A) conversa nova ✅: 3 tentativas com falha de conexão (~26 s entre elas), menu em 54 s. O cliente seguiu
    Atendimento → Financeiro → Atendente e foi transferido para o `financeiro`, com a marca do menu desligada. Tudo
    assinado pelo assistente.
  - B) outra conversa nova com a IA já marcada como fora ✅: menu em 1 s, sem esperar as tentativas.
  - C) conversa em andamento ✅: foi para atendente em 0,3 s, com a nota "Assistente virtual indisponível…" e a mensagem
    de transferência, sem menu.
  - D) conversa parada (job de resposta perdido) ❌→✅: na 1ª rodada, a varredura não agiu, porque os modelos automáticos
    do widget (coleta de e-mail) vinham depois da mensagem do cliente e contavam como resposta. **Correção:** modelos
    automáticos (saudação, fora do horário, coleta de e-mail) não contam como resposta; +1 spec. Na 2ª rodada, o menu
    foi enviado.
  - Restauração ✅: endpoint real de volta, marca de IA fora limpa, e a IA voltou a responder normalmente (endereço de
    Vila Velha e encerramento).
  - Pegadinha de teste: `rails runner` usa cache de consultas, e um laço de espera sem `uncached`/`reload` não vê as
    mensagens novas (o `e2e_fallback.rb` já trata isso).
- **Suítes:** 71 exemplos (fallback e runner), 0 falhas, depois da correção da varredura; o spec original do job de
  resposta segue verde. RuboCop limpo.
- **Para produção:**
  - Remover o `AgentBotInbox` do BotFlow da inbox 5 na troca para o Captain.
  - Aviso de migração do Moto Fácil no menu de reserva: **desligado** a pedido do usuário (11/09/2026), com
    `BOTFLOW_MOTOFACIL_ANNOUNCEMENT=false` no `.env` local. Em produção a variável não está definida, então o aviso está
    ligado, e o BotFlow ainda é o bot principal, usando o aviso para a triagem do Moto Fácil. Definir `false` no
    `.env.production` **na troca para o Captain**, junto com a remoção do `AgentBotInbox` (recriar os containers: a
    variável é lida no boot).
  - O 1º cliente de uma queda espera cerca de 1 min pelas tentativas; os seguintes recebem o menu na hora por 5 min.

## Placa e CPF antes de qualquer transferência (11/09/2026, regra do usuário)

- **Regra:** "sempre, antes de transferir para um humano, o bot tem que conseguir a placa da moto do cliente e seu CPF".
- **Decisões do usuário:**
  - Cliente que não tem ou não sabe o dado: o bot insiste uma vez e transfere com "não informada" / "não informado".
  - Socorro: pede a placa e o CPF junto com a localização.
  - IA fora do ar (menu de reserva ou transferência direta): não exige.
- **Implementação:**
  - `Captain::Conversation::CustomerIdentification` (novo):
    - lê as mensagens do cliente das últimas 24 h, incluindo transcrição de áudio;
    - aceita placa antiga (ABC-1234) ou Mercosul (ABC1D23), sem confundir "CPF 1234" ou "Rua 1234" com placa;
    - aceita CPF com ou sem pontuação e confere os dígitos verificadores;
    - quando falta algo, recusa com instrução para a IA: pedir os dois numa mensagem só, ou pedir de novo o que falta,
      avisando quando o CPF é inválido;
    - libera a transferência depois de uma insistência: 2 pedidos do bot com "placa" ou "CPF" e resposta do cliente
      depois do 2º.
  - Trava na `AssignTeamTool`, por onde passam todas as transferências (inclusive parcelas, troca de moto e socorro):
    - vale só enquanto o bot atende a conversa (pendente) e ainda não transferiu nesta rodada;
    - a nota para o time ganha a linha "Placa: … | CPF: …", copiada das mensagens do cliente, nunca escrita pela IA.
  - Diretriz nova para todos os agentes, e o cenário de socorro pede localização, placa e CPF juntos.
- **Testes:** identificação (8), `AssignTeamTool` reescrito (5) e specs das ferramentas que delegam atualizados. Com o
  spec do job de resposta e o de encerramento, são 93 exemplos, 0 falhas. RuboCop limpo.
- **Limitações:**
  - Placa ou CPF só em foto de documento não é lido; o bot pede para digitar.
  - Um telefone de 11 dígitos pode ser tomado por CPF: com dígito verificador inválido, o bot pede para conferir; na
    rara coincidência de dígito válido, passaria como CPF.
- **Simulações (IA real):**
  - **1ª rodada:**
    - contestação ✅: pediu placa e CPF antes de transferir → `financeiro`, com "Placa: ABC1D23 | CPF: 529.982.247-25"
      na nota. Detalhe: ao pedir os dados, disse "time de negociação";
    - CPF com dígito errado ✅: a trava recusou, o bot pediu para conferir, o cliente corrigiu → `financeiro`;
    - ❌ revisão sem placa: insistiu uma vez, mas perguntou se o cliente "prefere" ser transferido e depois anunciou a
      transferência sem chamar a ferramenta (o log não tem `assign_team` nessa conversa);
    - ❌ socorro: a diretriz geral fez o bot pedir placa e CPF antes de oferecer o socorro. Quando o cliente mandou
      endereço, placa e CPF juntos, a ferramenta de socorro recusou (o bot nunca tinha perguntado a localização) e ele
      pediu o endereço de novo.
  - **Correção 1 (diretriz):** pedir placa e CPF só na hora de transferir, depois dos passos do cenário, sem citar o
    time. Sem o dado depois de insistir, fazer a mesma transferência, para o mesmo time.
  - **2ª rodada:**
    - contestação ✅, sem citar time;
    - socorro ✅: pediu localização, placa e CPF juntos, e a nota trouxe os três como o cliente escreveu. A 1ª resposta
      ainda pediu placa e CPF antes de oferecer o socorro;
    - ❌ revisão sem placa de novo: "sem esse dado, não consigo prosseguir com o agendamento". A IA tratou a placa como
      condição do agendamento e nem tentou transferir.
  - **Correção 2:** a descrição da `AssignTeamTool` passou a dizer "se o cliente não tiver os dados depois de pedir duas
    vezes, chame mesmo assim". O passo de agendamento do cenário 3 passou a dizer que quem marca é o time de manutenção
    e que a falta de placa ou CPF nunca impede o encaminhamento.
  - **3ª rodada:** resultado a registrar.

### Simulações do Caso 6 (10/09/2026) — parei aqui

- **Renovação** ✅ (2ª rodada, com o número de vendas): *"não existe renovação de locação. Quando o senhor terminar a
  locação atual, poderá fazer uma nova locação pelo WhatsApp de vendas: (92) 2398-1266 … só é permitida uma locação por
  CPF"* → "algo mais?" → "não" → encerrada. Não sugeriu inadimplência.
- **Troca de moto** ❌: pediu o motivo com detalhes ✅, mas com o motivo vago ("Porque quero outra") **transferiu pro
  `pós-venda` mesmo assim** — a própria nota dizia "motivo fornecido é vago e precisa de mais detalhes". Mesmo padrão do
  print obrigatório do Caso 5. **Próximo passo:** ferramenta própria (como a `installment_dispute_transfer`) que exige o
  motivo declarado e recusa motivo curto/vago.
- 🐛 **Aviso de horário errado:** fora do expediente (quinta, depois das 18h) o bot disse que o time "retorna no próximo
  dia útil, **segunda-feira** às 08:00" — o certo era **sexta** 08:00. A `AssignTeamTool#confirmation` só entrega a grade de
  horários e manda a IA calcular quando o time volta; ela errou a conta. **Próximo passo:** calcular no servidor o próximo
  horário de abertura (dia + hora) e devolver pronto.
- **Recorrente:** "Posso ajudar em algo mais?" logo depois de transferir (apareceu de novo na troca), apesar da guideline.
  Candidato a ir no próprio texto de confirmação da transferência. → Resolvido em 11/09/2026 (`HandoffReplyTrimmer`, abaixo).

## Onde parei (10/09/2026) e como retomar

- Tudo **só local**, na branch `feat/captain-motofacil-access`, no **commit WIP `b1f99c1f2`** (sem push). Nada em produção.
  Pausado em 15/09/2026 para o PR #99 (certificado HTTPS). Para retomar: `git switch feat/captain-motofacil-access`. Se
  quiser as mudanças de novo fora de commit, use `git reset --soft HEAD~1`. A última rodada de simulações de placa e CPF
  (revisão sem placa e contestação sem CPF) foi interrompida e precisa ser refeita.
- Scripts da sessão salvos em `scripts/` desta pasta (sem credenciais). Como todo o `.ai/` (`.gitignore:112`), ficam **só
  nesta máquina**, não vão para o git:
  - `local_captain_setup.rb` — monta o assistente, os **6 cenários**, o horário espelhado e o `CaptainInbox` da inbox 95.
    É a **fonte de verdade do texto dos cenários** (servirá para criar em produção).
    Rodar: `docker compose exec -T rails bundle exec rails runner - < .ai/features/captain-motofacil-access/scripts/local_captain_setup.rb`
  - `e2e_roteiro.rb` (roteiro genérico via `E2E_NAME`/`E2E_LINES`/`E2E_EXPECT`/`E2E_FORBID`), `e2e_parcelas.rb`
    (print/comprovante com imagem por `external_url`), `e2e_v2.rb` e `e2e_c1_close.rb` (Caso 1), `e2e_negociacao.rb`.
- Ambiente: `docker compose up -d rails` + `pnpm exec vite dev` (ver `.ai/workflow.md`). Depois de mexer em ferramenta ou
  `tools.yml`: reiniciar `sidekiq` (e `rails`). Specs com `RAILS_ENV=test` explícito e **nunca junto com simulação** (Redis compartilhado).
- **Pendências:**
  1. ~~Troca de moto: ferramenta com motivo obrigatório~~ — feito em 11/09/2026 (abaixo).
  2. ~~Próximo horário de abertura calculado no servidor~~ — feito em 11/09/2026 (abaixo).
  3. ~~"Algo mais?" depois de transferir~~ — feito em 11/09/2026 (abaixo), cortado no servidor.
  4. ~~Decidir se o caminho completo do pagamento precisa ser determinístico~~ — descartado em 11/09/2026: o usuário quer
     resposta genérica, sem passo a passo (ver "Decisão de 11/09/2026" no Caso 5).
  5. Seguir para os próximos casos que o usuário trouxer.
  6. Caso 3: um pedido claro de agendar revisão às vezes recebe "Posso ajudar a agendar?" antes da transferência para a
     `manutenção` (1 de 2 em 11/09/2026).
  7. Em aberto por decisão do usuário: ouvidoria e reclamações, e os alertas de conversa sem resposta. Achado sem ação: o
     menu do BotFlow volta no meio do atendimento depois de uma transferência para time sem atendente.

### ✅ 11/09/2026 — troca de moto com motivo obrigatório e próximo horário de abertura no servidor

- **`motorcycle_swap_transfer`** (nova; a transferência em si é da `AssignTeamTool`): a IA informa o motivo e declara
  `reason_detailed`; o servidor recusa se o bot não perguntou o motivo (fala com "motivo/por que/razão" nas últimas 24 h),
  se o cliente não respondeu, ou se a resposta do cliente tem menos de 5 palavras — mesmo com a IA dizendo que é
  detalhado. Nota padronizada "Troca de moto — motivo: …". 6 specs. O cenário 6 usa só ela para troca.
- **Próximo horário de abertura** (`BusinessHoursReadable#next_opening_text`): calcula no fuso da inbox o próximo dia e
  hora em que o time abre ("hoje às 08:00", "amanhã (sexta-feira) às 08:00", "segunda-feira às 08:00"). A `AssignTeamTool`
  entrega esse texto pronto quando o time está fechado ("use exatamente esse dia e hora; não calcule"), e a
  `business_hours_check` também. Specs: 5 do concern (quinta à noite → sexta, sexta à noite → sábado, sábado 13h →
  segunda, madrugada → hoje, grade semanal) + 2 da `AssignTeamTool`. De brinde: o `schedule_text` fazia
  `reject { |_, text| text.nil? }` sobre **pares** e o RuboCop sugere `compact`, que manteria os dias fechados — trocado por
  `select(&:last)`, com comentário.
- **Simulações** (IA real; a sexta foi fechada temporariamente na inbox 95 e restaurada no fim):
  - **Troca de moto** ✅: pediu o motivo → "porque quero outra" → **não encaminhou**, pediu mais detalhes → motivo detalhado
    → encaminhou pro `pós-venda` com a nota do motivo. A recusa da ferramenta não precisou disparar (a IA não tentou
    antes). ⚠️ Menor: a resposta ao motivo vago juntou duas perguntas parecidas (duas respostas estruturadas publicadas juntas).
  - **Aviso com o time fechado** ✅: contestação → financeiro → "retorna **amanhã (sábado) às 08:00**"; na troca, o mesmo
    para o pós-venda. Nada de "segunda".
  - ⚠️ Nas duas: "Posso ajudar em mais alguma coisa?" logo depois de transferir (pendência 3).
- Suítes das rodadas: 27 e 13 exemplos (troca, parcelas, encerramento, `AssignTeamTool`, horário), 0 falhas; RuboCop limpo.

### ✅ 11/09/2026 — áudio: o agente "ouve", e as travas não podem ser surdas

- **O Captain recebe a transcrição dos áudios:** o `Captain::OpenAiMessageBuilderService` troca cada áudio do cliente pelo
  texto do `Messages::AudioTranscriptionService`, que **reaproveita** a transcrição salva no anexo
  (`meta['transcribed_text']`) ou transcreve na hora (e salva) antes de a IA rodar. Exige `captain_integration` e
  `account.audio_transcriptions`. Produção (conta 1): ligado; 203 de 206 áudios dos últimos 3 dias com transcrição salva.
  **Local (conta 47) estava desligado** — nenhuma simulação anterior tinha áudio. Ligado, e o script de montagem liga também.
- **Buraco encontrado na `motorcycle_swap_transfer`:** ela media a resposta do cliente só pelo `content` das mensagens; um
  motivo explicado **por áudio** chega sem texto e seria recusado como "vago". Agora soma as transcrições salvas dos áudios
  (+1 spec). As outras travas não têm esse problema: a do Caso 1 só exige que exista resposta, a do Caso 5 conta imagens, a
  do encerramento só procura "?".
- **Pegadinha de teste (não é bug de produção):** anexo de áudio **sem arquivo** quebra o `Attachment#audio_metadata` (lê
  `file.metadata` sem checar se há arquivo) no broadcast da mensagem. Áudio do WhatsApp sempre vem com arquivo; em spec e
  simulação, anexar um arquivo (`file: { io: StringIO.new(...), content_type: 'audio/ogg' }`).
- **Simulação** ✅: "quero trocar a moto" → bot pede o motivo → cliente manda **só um áudio** (transcrição salva, sem voz
  pt-BR no Windows para gerar áudio real) → a IA usou a transcrição → `motorcycle_swap_transfer` aceitou → `pós-venda` com a
  nota do motivo; a transcrição salva não foi refeita. A transcrição do Azure em si não foi exercitada localmente (já
  comprovada em produção). ⚠️ De novo "Posso ajudar em mais alguma coisa?" depois de transferir (pendência 3).

### ✅ 11/09/2026 — "Posso ajudar em mais alguma coisa?" depois de transferir (pendência 3)

A guideline e os cenários já mandavam não perguntar depois de transferir, e a IA perguntou em **todas** as simulações de
transferência de 11/09. Resolvido no servidor, em duas camadas:
- **`Captain::Conversation::HandoffReplyTrimmer`** (novo): remove do **fim** da resposta a pergunta de "algo mais / mais
  alguma / ajudar em algo" (última frase terminada em "?"), preservando o texto antes e as quebras de linha; nunca devolve
  resposta vazia; não mexe em oferta que não seja a frase final.
- **`Captain::Conversation::MessageBuilder#create_messages`** (upstream, patch pequeno): aplica o trimmer **só** quando a
  conversa tem a marca `captain_handoff_pending` — deixada pela `AssignTeamTool` (e, por tabela, pela
  `installment_dispute_transfer` e pela `motorcycle_swap_transfer`) durante a mesma rodada. Lê a marca direto do banco
  (`uncached`), porque o `@conversation` do job foi carregado antes da ferramenta rodar. Sem transferência, o "algo mais?"
  continua — é ele que libera o encerramento.
- **Reforço no texto:** a confirmação da `AssignTeamTool` agora diz "A person from the team takes over: do not ask the
  customer whether you can help with anything else".
- Specs: 5 do trimmer + 2 no `response_builder_job_spec` (com transferência corta; sem transferência mantém); o spec inteiro
  do job (upstream) e os das ferramentas de transferência/encerramento seguem verdes — 82 exemplos, 0 falhas; RuboCop limpo.
- **Simulações** (IA real, Sidekiq reiniciado):
  - **Contestação → financeiro** ✅: *"Encaminhei seu pedido para o time financeiro. Um atendente vai continuar o
    atendimento com o senhor."* — sem "algo mais". No log do Sidekiq, a saída **bruta** da IA ainda trazia uma 2ª resposta
    estruturada *"Posso ajudar em algo mais, senhor?"*: foi o trimmer que cortou (o reforço no texto sozinho não segurou).
  - **Troca de moto → pós-venda** ✅: pediu o motivo → motivo detalhado (embreagem, duas idas à oficina) → nota do motivo →
    *"Seu pedido de troca foi encaminhado para o time de pós-venda. Um atendente vai continuar..."*. Aqui a IA já não
    tinha escrito a oferta.
  - **Endereço de Vila Velha (sem transferência)** ✅: manteve *"Posso ajudar em mais alguma coisa?"* → "não, era só isso"
    → despedida → encerrada pela `close_conversation`. O corte não afeta quem não foi transferido.

### ✅ 11/09/2026 — pagamento genérico e roteamento entre pagamento e negociação

- **Decisão do usuário:** resposta de pagamento genérica, sem passo a passo (ver "Decisão de 11/09/2026" no Caso 5). O
  cenário 5 passou a pedir link + "parte de cobranças" + "opção de recibo", terminando com "Posso ajudar em algo mais?". Tem
  um exemplo para pagar e outro para recibo, e o pedido de print não cita nome de tela.
- **1ª rodada:** o "Só isso." no cenário fez o bot parar de perguntar "algo mais?" (sem a pergunta ele não encerra), e o
  pedido de recibo copiou a frase do pagamento. Corrigido com "termine a mesma mensagem perguntando se pode ajudar em algo
  mais" e com o exemplo de recibo.
- **2ª rodada, o problema era roteamento:** o `agent_name` das mensagens (`additional_attributes`) mostrou que as respostas
  erradas ("Posso enviar o link?", recibo sem cobranças) vinham do **orquestrador** (`mobilli`), que respondeu sozinho sem
  repassar ao cenário. Causas: a guardrail de pagamento trazia a resposta pronta ("pagamento só na plataforma + link"), e
  "diárias" não estava no gatilho do cenário.
- **Armadilhas do Captain v2 (valem para os próximos casos):**
  - `assistant.description` só aparece no prompt do **orquestrador** (`assistant.liquid`). Já `guardrails` e
    `response_guidelines` vão para o orquestrador **e** para todos os cenários (`scenario.liquid`). Regra de roteamento vai na
    descrição do assistente e na do cenário, nunca numa guardrail.
  - Guardrail com a resposta de um assunto faz o orquestrador responder sozinho em vez de repassar. A guardrail deve ter só
    a proibição.
  - A descrição do assistente e a do cenário têm no máximo 500 caracteres (`DESCRIPTION_LENGTH_LIMIT`). Estourar o limite
    derruba o script de montagem no `assistant.save!`, e **nada** depois disso é aplicado. Uma rodada inteira de simulação
    rodou com a configuração antiga antes de eu notar. Agora a rodada para se a montagem falhar e confere no banco se o
    texto novo entrou.
  - Gatilho amplo ("qualquer assunto de pagamento") roubou a contestação de valor, que é do cenário de negociação: o bot
    pediu print e encerrou sem transferir.
- **Correções (só dado, `scripts/local_captain_setup.rb`):**
  - Descrição do assistente (423 caracteres): "nunca responda você mesmo sobre pagamentos", mais o que vai para "Pagamento,
    parcelas e recibos" e o que vai para "Negociação, vencimento e parcelamento".
  - Guardrails: "Nunca informe valores de cobranças nem envie boleto ou pix pelo chat." e "Nunca pergunte se pode enviar um
    link: quando o link ajuda o cliente, envie direto."
  - Cenário 5: o gatilho inclui diárias, como ou onde pagar e comprovante, e diz que "não inclui contestar valor, desconto,
    promoção, mudar vencimento ou negociar". Nas instruções, esses casos voltam para o assistente principal.
  - Cenário 2: passos reordenados. 1º contestação, promoção ou desconto vão para o `financeiro` sem explicar a regra; 2º
    vencimento, parcelamento ou negociação recebem a explicação e o "algo mais?"; 3º insistência. Antes, a promoção recebia a
    explicação da regra em vez de ir para o financeiro.
- **Rodada final (7 de 7 ✅, `agent_name` conferido):**
  - contestação (2 conversas) e promoção → cenário 2 → `financeiro`, sem "algo mais";
  - vencimento → cenário 2 → explica, pergunta "algo mais?" e encerra;
  - recibo e diárias → cenário 5 → resposta genérica, "algo mais?" e encerra;
  - parcela paga em aberto → cenário 5 → pede as parcelas, o print da tela de cobranças e o comprovante (opcional).

  Nenhuma resposta cita abas, botões ou "Minhas Cobranças".

### Simulações dos Casos 3 e 4 (10/09/2026)

- **Endereço de Vila Velha** ✅: rua, número, CEP e referência (container da Mobílli, em frente à Cibien Motors) + "posso
  ajudar em mais alguma coisa?" na mesma mensagem → "não" → despedida → encerrada.
- **Oficina + loja da Serra** ✅: horário da oficina (8h–12h, almoço até 13h, até 17h30; sábado como as lojas) → endereço
  da Serra com a Yamaha e **sábado 8h–12h vindo da `business_hours_check`** (horário configurado na inbox) → encerrada.
- **Cliente que quer trocar de moto** ✅: não passou o número de vendas; transferiu pro `pós-venda`.
- **Vendas — 1ª rodada** ❌: passou o (92) 2398-1266 com link, sem preço, e já explicou a filial de Manaus; mas quando o
  cliente perguntou *"Mas esse DDD 92 não é de Manaus?"*, o bot **encerrou a conversa sem responder**, registrando como
  motivo "cliente não respondeu após esclarecimento".

### 🔴 Trava no servidor para o encerramento

Mesma lição do Caso 1: ação que tira o cliente do atendimento não fica só na instrução. A `close_conversation` agora
recusa quando:
- a **última mensagem do cliente tem "?"** → devolve à IA "responda a pergunta primeiro";
- a **última fala pública do assistente antes dela não perguntou se podia ajudar em algo mais**
  (`algo mais|mais alguma|posso ajudar|ajudar em algo`) → devolve "pergunte primeiro".

Se a resposta do cliente foi mesmo um "não" continua a critério da IA. Specs da ferramenta: 7 exemplos (incluindo o caso
exato do DDD e o encerramento sem a pergunta final).

Depois da trava (sidekiq reiniciado):
- **Vendas — 2ª rodada** ✅: *"Mas esse DDD 92 não é de Manaus?"* → *"Exatamente, o DDD 92 é de Manaus, onde a Mobílli
  também possui uma filial..."* + "algo mais?" → "não" → encerrada. (A recusa da ferramenta não é logada, então não dá pra
  afirmar se a trava chegou a disparar nesta rodada — o comportamento certo está coberto pelos specs.)
- **Vila Velha — 2ª rodada** ✅ (regressão): encerramento normal continua funcionando com a trava.
- **Oficina: agendar revisão no sábado** ✅ (regra confirmada pelo usuário): *"A oficina funciona no sábado apenas para
  tratar casos pendentes, não é possível agendar atendimento para esse dia. Posso ajudar a agendar sua revisão para um dia
  de semana?"* → "não, era só isso" → encerrada. Obs.: a trava do encerramento aceitou "Posso ajudar a agendar…" como a
  pergunta de "algo mais" (o padrão casa "posso ajudar"). Mantido de propósito: o cliente já tinha dito que era só isso, e
  exigir outra pergunta só acrescentaria um passo.

## Caso 5 — pagamento, parcelas e recibos (10/09/2026)

Regra passada pelo usuário (com uma correção no meio):
- Pagamento e consulta de parcelas **só pela plataforma Moto Fácil** (`https://www.motofacil.club/auth`). Nada de pagamento
  pelo chat. As cobranças ficam na aba **"Cobranças"**; o **recibo** de um pagamento feito é emitido lá.
- Cliente diz que **falta parcela** ou que **parcela paga aparece em aberto** → o bot pede **quais parcelas (obrigatório)**,
  **print do aplicativo (obrigatório)** e **comprovante (opcional)**; só com os obrigatórios transfere para **`suporte app`**
  (a primeira versão assumia financeiro; o usuário corrigiu).
- A guardrail antiga "boletos/links de pagamento vão pro financeiro" virou "nunca envie valor, boleto, pix, fatura ou link
  de pagamento pelo chat: pagamento e consulta são só na plataforma" — a antiga conflitava com o bot orientar o pagamento.
- **Como a plataforma aparece para o cliente** (print enviado pelo usuário em 10/09/2026; nenhum dado dele copiado): "Meu
  Painel" → seção **"Minhas Cobranças"**, com as abas **A Vencer / Vencidas / Pagas / Isentas**. Pagar o atrasado: aba
  **Vencidas** → marcar as diárias → **"Pagar Selecionadas"**. **Recibo** (confirmado pelo usuário): aba **Pagas** → tocar na
  cobrança paga → aparece a opção de emitir o recibo. **Não existe uma aba chamada "Cobranças"** — as primeiras versões do
  cenário diziam isso; o cenário e o pedido de print ("tela Minhas Cobranças, na aba em que a parcela aparece") passaram a
  usar os nomes reais.
- **Decisão de 11/09/2026 (usuário): sem passo a passo.** A UX/UI da plataforma pode mudar e o agente ficaria
  desatualizado. O bot só diz, curto e direto, que o pagamento é **na plataforma** (com o link), **na parte de cobranças**,
  e que ali **tem a opção de recibo**. O cenário não cita mais abas, botões, nomes de tela nem passo a passo — nem no
  pedido de print ("captura da tela de cobranças do Moto Fácil em que a parcela aparece"). Os nomes do item acima ficam só
  como registro de como era a tela em 10/09. Com isso a pendência 4 (caminho completo em 2 de 3) deixou de existir.
- Só dado: cenário "Pagamento, parcelas e recibos".

**Imagens (print/comprovante):** o Captain passa imagem para a IA **por URL**
(`Captain::OpenAiMessageBuilderService#get_attachment_url`: `download_url` → `external_url` → `file_url`). Em produção a URL
é do Azure Storage (alcançável pela Azure OpenAI). **No local, arquivo anexado vira URL de `localhost`, que a IA não
alcança** — para simular um print, a mensagem de teste leva um anexo `image` com `external_url` de uma imagem pública
gerada (placehold.co, texto sintético "Moto Fácil · Cobranças · Parcela 05/09 · Em aberto", sem dado real).

Simulações:
- **P1 — boleto e recibo** (1ª rodada): recusou boleto pelo chat, mandou pagar e pegar recibo na plataforma e encerrou ✅,
  mas **não passou o link nem citou a aba "Cobranças"** ❌ — provável efeito da guardrail "nunca envie link de pagamento"
  (o modelo leu o link de acesso como link de pagamento). Passo 1 do cenário agora diz que o link é de acesso, não de
  pagamento, e deve ser sempre enviado, junto com a aba "Cobranças".
- **P2 — parcela paga aparece em aberto** (1ª rodada): pediu parcelas, print e comprovante (opcional) ✅; quando o cliente
  disse "segue o print" **sem imagem**, notou que nada chegou, mas **pediu o comprovante** como se fosse obrigatório ⚠️;
  só transferiu pro `suporte app` depois que a imagem chegou ✅; porém a **nota interna dizia "comprovante de pagamento
  enviado"** quando o que chegou foi o **print do app** ❌ (o time seria induzido a erro). Nenhum erro da IA com a imagem
  externa. Obs.: a verificação automática desta rodada deu falso positivo no passo "pediu de novo" (só casava "envie").
  Correção no cenário: define print (tela do Moto Fácil com as cobranças) × comprovante (recibo do banco/pix), manda olhar
  a imagem para saber qual chegou, reforça que o comprovante é opcional e padroniza o motivo da transferência com
  "print do aplicativo: recebido" / "comprovante: recebido|não enviado".
- **P1 — 2ª rodada** (com o link liberado no cenário): na pergunta do **recibo** passou o link e citou a aba "Cobranças" ✅,
  mas na **primeira resposta** ("como faço pra pagar? me manda o boleto?") repetiu só "não enviamos boletos ou links de
  pagamento" **sem o link** ⚠️ — a guardrail ainda vence a instrução justamente na hora de recusar o boleto. Correção: a
  própria guardrail passa a dizer que o link de acesso deve sempre ser enviado, e o passo 1 manda incluir link e aba "já na
  primeira resposta, inclusive quando recusar o boleto".
- **P2b — manda o comprovante antes do print** ❌: a IA **reconheceu a imagem** (nota: "print do aplicativo: não recebido,
  comprovante: recebido" — prova de que a leitura de imagem por URL funciona) e mesmo assim **transferiu pro `suporte app`
  sem o print obrigatório**. Mesmo padrão dos Casos 1 e 4: instrução não segura regra.
- **P2c — manda só o print do app** ✅: transferiu sem exigir comprovante, nota "print do aplicativo: recebido, comprovante:
  não enviado".
- **Decisão:** trocar o `assign_team` deste cenário por uma ferramenta própria em que a IA declara `installments`,
  `app_screenshot_received` e `receipt_received`; o servidor recusa sem parcelas, sem print declarado, sem nenhuma imagem do
  cliente, ou com uma única imagem declarada como print **e** comprovante; a nota da transferência sai padronizada pelo servidor.
  Feito: `installment_dispute_transfer` (reaproveita a `AssignTeamTool` para a transferência; loga também as recusas), 8 specs.
- **P1 — 3ª rodada** ❌ → **causa era um bug meu**: a resposta publicada foi só "Posso ajudar em mais alguma coisa, senhor?".
  O log do Sidekiq mostrou a saída bruta: a IA **tinha respondido certo** ("acesse a plataforma Moto Fácil pelo link
  https://www.motofacil.club/auth…") e emendou uma segunda resposta estruturada com o "algo mais?". A correção do JSON cru
  (`AgentRunnerService#response_from_text`) ficava **só com a última** e jogava a resposta de verdade fora. Provavelmente foi
  o mesmo que fez a N2 da 1ª rodada "ignorar" o pedido de exceção (hipótese, não conferida no log). Corrigido: publica
  **todas** as respostas estruturadas, na ordem, sem repetir iguais; specs do serviço atualizados.
- **P2b — 2ª rodada, com `installment_dispute_transfer`** ✅: 1ª resposta já trouxe o link e a aba "Cobranças" e pediu
  parcelas + print; com o **comprovante** respondeu "recebi o comprovante, mas preciso também do print do aplicativo" e
  **não encaminhou**; com o **print** encaminhou pro `suporte app` com a nota padronizada "Parcelas: parcela de 05/09 | print
  do aplicativo: recebido | comprovante: recebido". A recusa da ferramenta **não chegou a disparar** (a IA nem tentou antes
  do print) — o bloqueio segue coberto pelos specs.
- **P2c — 2ª rodada** ✅: só o print → encaminhou sem exigir comprovante, nota "comprovante: não enviado". ⚠️ Menor: a
  mensagem da transferência terminou com "Posso ajudar em algo mais?" (a guideline diz para não perguntar depois de
  transferir). As duas rodadas ainda eram antes do Sidekiq carregar a correção das respostas múltiplas.
- **P1 — 4ª rodada** (com a correção das respostas múltiplas carregada) ❌: resposta única (0 saídas com várias respostas
  no log) — *"o pagamento das parcelas deve ser feito pela plataforma Moto Fácil. **Posso enviar o link para o acesso?**"*:
  pediu permissão em vez de mandar. Somando as rodadas, para "como pago? me manda o boleto?" só 1 de 3 saídas brutas trouxe
  o link. A tensão com "não envie link de pagamento" continua → a guardrail perdeu o "link de pagamento" (fica "nunca envie
  valor, boleto ou pix; o link de acesso vai direto, sem perguntar") e o passo 1 ganha "não pergunte se pode enviar o link"
  com um exemplo de resposta. Por ser não determinístico, a verificação passa a rodar a mesma pergunta 3 vezes.
  (O "failed" da tarefa foi artefato do comando: um `grep -c` com 0 resultados sai com código 1.)
- **P1 — 5ª rodada, 3 execuções da mesma pergunta** (guardrail sem "link de pagamento" + passo 1 "não pergunte, envie" com
  exemplo): **link enviado direto nas 3** ✅ (antes: 1 em 3, e uma pedindo permissão); aba **"Cobranças" citada em 1 das 3**
  ⚠️ (a que repetiu o exemplo quase literal); nenhuma pediu permissão nem mandou valor. A 3ª emendou "Posso ajudar em mais
  alguma coisa?" na mesma mensagem — pelo espaçamento, eram duas respostas estruturadas **preservadas juntas** pela correção
  (antes a primeira teria sido descartada) — e encerrou depois do "não". (A "aba Cobranças" nem existe — ver a navegação
  real acima.)
- **P1 — 6ª rodada, 3 execuções, com a navegação real** ("Minhas Cobranças" → "Vencidas" → "Pagar Selecionadas"): **link
  direto nas 3** ✅, nenhuma com valor nem "aba Cobranças"; **caminho completo em só 1 das 3** ⚠️ (a que repetiu o exemplo);
  as outras pararam em "acesse o link para consultar e pagar". Próxima tentativa (só instrução): o passo 1 lista o que a
  resposta **tem que conter** (link, Minhas Cobranças, Vencidas, Pagar Selecionadas; recibo: link, aba Pagas, tocar na
  cobrança paga). Se continuar variando, a saída é determinística (texto fixo devolvido por ferramenta).
- **Recibo** ✅ (com o local confirmado pelo usuário): *"O recibo do pagamento feito está disponível na plataforma Moto
  Fácil: https://www.motofacil.club/auth. Após entrar, vá em 'Minhas Cobranças', na aba 'Pagas', e toque na cobrança paga
  para emitir o recibo."* — caminho completo na primeira resposta.
- **P1 — 7ª rodada, 3 execuções** (passo 1 com o conteúdo obrigatório listado): **link direto nas 3** ✅; **caminho
  completo (Minhas Cobranças → Vencidas → Pagar Selecionadas) em 2 das 3** ✅ (antes 1 de 3), sempre sem valores e sem
  "aba Cobranças". A que falhou deu só o link + "posso ajudar em mais alguma coisa?" e, no "não", **despediu-se sem
  encerrar**; só encerrou quando o cliente repetiu o "não" (a recusa do `close_conversation` não é logada, então não dá
  para dizer se a IA nem chamou a ferramenta ou se a trava recusou). Caminho determinístico (texto fixo por ferramenta)
  segue como opção se 2 de 3 não bastar.

## Pendências para produção (nada disso foi feito)

1. Conta de serviço do bot no Moto Fácil + variáveis `MOTOFACIL_*` no `.env.production` (sem a flag de dev).
2. Criar assistente/cenário em produção (dado, não código) e decidir o `captain_auto_resolve_mode`.
3. Trocar o BotFlow pelo Captain na inbox 5 (`AgentBotInbox` → `CaptainInbox`) — só depois dos outros casos além do Caso 1.
4. Decidir a limpeza da mensagem de credenciais (risco acima).
