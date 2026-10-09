# Captain (IA nativo do Chatwoot) — Status

> Ver `plan.md` para a arquitetura (como o bot é montado, armadilhas, escolha de modelo). Este arquivo é o log vivo.

## Estado atual (14/07/2026 em diante)

> ⚠️ **05/10/2026 — o aprendizado por conversa resolvida (PR #45) estava morto desde o upgrade
> v4.18.0.** O upstream renomeou `generate_and_deduplicate` → `generate_suggestions` e o nosso
> `CaptainLearningListener` ficou no nome antigo: **5.367 jobs mortos**, um por conversa resolvida,
> e **zero FAQ ou sugestão gerada** de 29/09 a 05/10. Corrigido no PR #119 (job próprio na fila
> `low`, primeiro spec do listener), validado em produção com tráfego real no mesmo dia. Não há o
> que reprocessar: as conversas já estão resolvidas e sugestão de FAQ não tem valor retroativo.
>
> 📌 **Duas coisas que eu afirmei no PR #119 e depois medi como ERRADAS** (ficam aqui para não
> serem repetidas):
> 1. *"o `Captain::ReportingEventListener` nunca rodou"* — **falso**. Ele não escuta
>    `conversation_resolved`, escuta `captain_conversation_resolved`, então nunca foi candidato a
>    esse evento. Medido: dos 13 listeners do `Enterprise::AsyncDispatcher`, só 5 respondem a
>    `conversation_resolved`, e o `CaptainLearningListener` é o **12º**, com o 13º fora da lista
>    desse evento. **Nenhum listener foi prejudicado pela posição.** Wisper só chama o subscriber
>    que `respond_to?` o método do evento — conferir isso antes de afirmar que algo foi bloqueado.
> 2. *"o retry duplicou `reporting_events`"* — **não foi este bug**. Existem 4.671 conversas com
>    `reporting_event` de resolução duplicado **de antes do upgrade** (pior caso 28), contra 410
>    depois. É fenômeno pré-existente e separado, ainda sem causa apurada → pendência abaixo. E o
>    job morria em **4 tentativas**, não nas 25 que eu supus.
>
> 💡 Este foi o terceiro problema do upgrade v4.18.0 descoberto depois do deploy (os outros dois:
> migrations rodadas no banco errado e a marca revertida pelo job noturno) — **o que o upgrade
> quebra em silêncio aparece no Sidekiq, não na tela**; vale olhar a fila de mortos, agrupada por
> erro, depois de cada upgrade.

### 🔎 Pendência aberta, não investigada: `reporting_event` de resolução duplicado

Achado de passagem em 05/10/2026, **não é do PR #119 e não foi apurado**: há 20.752
`reporting_events` de `conversation_resolved` para 15.099 conversas resolvidas, com **4.671
conversas duplicadas já antes do upgrade** e até 28 registros na mesma conversa. Reabrir e resolver
de novo duplica legitimamente, mas 28 vezes não se explica assim. Importa porque esses registros
alimentam os relatórios de tempo de resolução. Para investigar: comparar a contagem com as
atividades "marcada como resolvida" de cada conversa.

> 📎 Achado colateral do mesmo dia: `status_changed_at` é **nulo em 9.527 das 15.099** conversas
> resolvidas — a coluna chegou no upgrade v4.18.0 e só é populada desde 29/09. Não é defeito, mas
> qualquer relatório ou consulta que use esse campo como filtro de data **não vê nada anterior a
> 29/09/2026**.

**🤖 Captain em STANDBY, sendo refinado fora do ar. O bot de triagem ativo é o [[bot-flow]].**

Rodou em produção de 13/07 a 14/07/2026. Desligado a pedido do usuário — *"vamos manter o bot que tava... deixa esse [Captain] como está, mas só desativa. A gente vai aprimorando ele e deixa o outro em produção, pois já temos que lançar essa semana"*. **Não foi por bug crítico** — o Captain estava funcional, só não era hora de arriscar numa semana com lançamento não relacionado. Na hora só a inbox foi desvinculada — **mas os cenários e as FAQs não existem mais em produção** (ver "🔴 Base de conhecimento apagada" abaixo). Sobreviveram o assistente (descrição, guardrails, guidelines, config) e as ferramentas, que são código.

| | |
|---|---|
| Assistente | **"Mobílli"** (`Captain::Assistant` id 2), guardrails e guidelines intactos, **0 cenários** (eram 9) — **NÃO está pronto pra religar** |
| Base | **0 FAQs** (22 chegaram a ser criadas), 0 documentos |
| Ferramentas nossas | `assign_team`, `crm_lookup`, `business_hours_check` (+ nativas `faq_lookup`, `resolve_conversation`, `add_label_to_conversation`) |

### 🔜 Para religar (um comando)

> ⚠️ **Não rode sem reconstruir os cenários antes.** Sem cenário o roteador não tem `assign_team` e só *promete* transferir (`plan.md`, armadilha #4). E confira o id da inbox: em julho o WhatsApp era a inbox 1, e desde a migração do Octadesk (03/08/2026) o WhatsApp de produção é a **inbox 5**.
```ruby
AgentBotInbox.where(inbox_id: 1).destroy_all
CaptainInbox.create!(inbox_id: 1, captain_assistant_id: 2)
```

### 🔙 Para devolver ao BotFlow de novo (um comando)
```ruby
CaptainInbox.destroy_all; AgentBotInbox.create!(inbox_id: 1, agent_bot_id: 2)
```

Os dois lados coexistem sem apagar nada — é só qual está vinculado à inbox 1.

### ⚠️ Pendência conhecida ao religar

O cenário **"Falar com Atendente"** manda perguntar o assunto quando não estiver claro, mas na prática o bot às vezes pula direto pra um time chutado (viu "pós-venda" sem contexto). Suspeita: confusão entre o guardrail *"não peça confirmação pra transferir"* (pedido explícito de humano) e o passo que pede pra perguntar o assunto — coisas diferentes, tratadas como igual. Ajustar o texto do cenário #8 antes de religar pra valer.

### 🔴 Base de conhecimento apagada (achado 10/09/2026)

Achado enquanto avaliava usar o Captain pra automação. Conferido no banco de produção pelas
sequences de id, que mostram quantas linhas já foram criadas mesmo que tenham sido apagadas depois:

| Tabela | Linhas hoje | Ids já emitidos |
|---|---|---|
| `captain_assistants` | 1 (só o #2) | 2 |
| `captain_scenarios` | **0** | 9 |
| `captain_assistant_responses` (FAQs) | **0** | 22 |
| `captain_documents` | 0 | 0 |
| `captain_faq_suggestions` | 0 | 0 |

- **FAQs pendentes**: apagadas pela migration **upstream** `20260714123000_purge_pending_captain_assistant_responses`
  (PR upstream #15017, tela de revisão de sugestões de FAQ): `DELETE ... WHERE status = 0`. O
  upstream tirou `pending` do enum (hoje só existe `approved`) e passou as sugestões pra tabela nova
  `captain_faq_suggestions`. Chegou no fork por upgrade e rodou no `db:migrate` normal (está em
  `schema_migrations`).
- **FAQs aprovadas e os 9 cenários**: causa **não identificada**. A migration não toca em aprovada
  (status 1) nem em cenário, a tabela `audits` não tem nenhum registro de Captain e o
  `Trash::CleanupJob` só purga conversa. O assistente #2 continua existindo, então não foi o
  `dependent: :destroy_async`. Suspeita sem prova: exclusão pelo painel ou numa limpeza (a inbox
  Bot Lab também foi apagada sem querer numa limpeza).
- **Sem backup pra restaurar**: o Postgres é o container `chatwoot-db` da VM, sem PITR e sem dump em
  `/opt/chatwoot`.
- **Dá pra remontar o texto**: os scripts `rails runner` que criaram os cenários estão no transcript
  da sessão do Claude Code (`d3154f5a-...jsonl`). Refinamentos feitos depois com `update!` precisam
  ser conferidos um a um.
- **`captain_faq_suggestions` nunca recebeu nada**: o aprendizado com conversas resolvidas
  ([[project_captain_learning]]) está quebrado desde o upgrade. O listener chama um
  `generate_and_deduplicate` que não existe mais (~2870 `EventDispatcherJob` mortos no Sidekiq).

### ✅ Migrado pra Azure OpenAI (04/09/2026) — resolve o crédito, menos transcrição

Provedor trocado da OpenAI direta pro **Azure OpenAI** (recurso `ai-mobilli-prod-eus2`, kind
AIServices/Foundry, S0 pay-per-token, RG `rg-mobilli-ai-prod`). Região **eastus2** e não eastus:
o modelo de transcrição não existe em eastus — testado de verdade, o deploy falha com
`The specified SKU 'Standard' for model 'whisper 001' is not supported in this region 'eastus'`.

Config em produção (`InstallationConfig`): `CAPTAIN_OPEN_AI_ENDPOINT` =
`https://ai-mobilli-prod-eus2.cognitiveservices.azure.com/openai` (**sem `/v1`** — ver
`.ai/fixes-log.md`, PR #97), `CAPTAIN_OPEN_AI_API_KEY` = chave do recurso novo. Deployments criados
com o **mesmo nome dos modelos** que o `config/llm.yml` referencia, pra não precisar tocar em
código: `gpt-4.1`, `gpt-4.1-mini`, `gpt-4.1-nano`, `gpt-5.2`, `text-embedding-3-small`,
`gpt-4o-mini-transcribe`.

**Hook da integração OpenAI desabilitado de propósito.** `Captain::BaseTaskService#llm_credential`
prefere a chave do hook (`account.hooks` `app_id: 'openai'`, `status: 'enabled'`) sobre a do
`InstallationConfig` — e **8 serviços** herdam isso (`sentiment`, `label_suggestion`,
`reply_suggestion`, `summary`, `rewrite`, `csat_utility_analysis`, `follow_up`,
`overview_summary`). Com o hook ativo eles continuavam batendo na conta OpenAI morta mesmo com o
resto migrado. Desabilitando, caem no `system_llm_credential` (Azure) — uma fonte de verdade só.
Sem impacto de quota: `responses_available?` (`enterprise/lib/enterprise/captain/base_task_service.rb:18`)
retorna `true` fora do Chatwoot Cloud, e nós somos self-hosted. Não desliga feature nenhuma — o
hook só é lido nesse ponto (`base_task_service.rb:201`).

Validado em produção após a virada: embedding (1536 dims), sentimento (`{sentiment: 3,
confidence: 0.9}`), copilot (`gpt-4.1-mini` respondendo), cliente legado/PDF — todos OK.

Rollback (se precisar): endpoint `https://ai-mobilli-prod.cognitiveservices.azure.com/openai`,
chave iniciada em `3SoYYz`, hook `enabled`. O recurso antigo em eastus foi mantido de propósito.

### ✅ Transcrição de áudio no Azure — resolvida (PR #98, 04/09/2026)

Client próprio dentro do `Messages::AudioTranscriptionService` quando o endpoint é Azure
(`api_type: :azure`, `uri_base` com `/deployments/{modelo}`, `?api-version=2024-06-01`), detectado
pelo host — instalação na OpenAI nativa segue inalterada. O client compartilhado do
`LegacyBaseOpenAiService` fica como está (serve o upload de PDF, que funciona no `/v1`).

Confirmado em produção: **tudo antes das 19:07 UTC sem transcrição, tudo a partir de 19:07 OK**
(última falha no dead set: 19:07:29). Áudio real transcrito corretamente em português.

**Backlog reprocessado (04/09/2026)**: em duas etapas, porque o dead set não cobria tudo — primeiro
`retry` nos 665 jobs mortos de `AudioTranscriptionJob` (dead job não retenta sozinho), depois
`perform_later` direto nos 442 anexos que sobraram sem transcrição e sem job correspondente (o dead
set tem limite de tamanho/idade, então os mais antigos já tinham sido descartados). Resultado:
**1080 de 1086 áudios transcritos**, fila zerada. Os ~6 que restaram falham individualmente
(provável arquivo corrompido/formato não suportado) — o job é idempotente, dá pra retentar quando
quiser sem risco de duplicar.

**Recurso antigo removido**: `ai-mobilli-prod` (eastus) deletado em 04/09/2026, depois de varrer
todas as Function Apps e Web Apps da subscription em busca de referências ao endpoint/chave antigos
— nenhuma encontrada (a varredura cobre app settings; referência por Key Vault ou hardcode no
código não seria detectada). Está em **soft-delete**: recuperável por um período e o nome segue
reservado até o purge.

### Diagnóstico original (mantido pelo valor do achado) — bloqueio de rota, não de região

Migrar pra eastus2 era **necessário mas não suficiente**. O Azure não expõe transcrição na camada
OpenAI-compatível: mesmo arquivo, mesma chave, mesmo recurso —
`POST /openai/v1/audio/transcriptions` → **404**, enquanto
`POST /openai/deployments/gpt-4o-mini-transcribe/audio/transcriptions?api-version=...` → **200**.
E `Messages::AudioTranscriptionService` chama via gem `ruby-openai`
(`@client.audio.transcribe`), que monta justamente a rota `/v1/...`. Confirmado no código real, não
só no curl: `Faraday::ResourceNotFound: 404 for POST .../openai/v1/audio/transcriptions`.

O gem **suporta** modo Azure (`api_type: :azure` → `uri_base + path + ?api-version=`, header
`api-key`), mas aí o `uri_base` precisa embutir `/deployments/{modelo}` — que é **por modelo**, e
`Llm::LegacyBaseOpenAiService` monta **um client só** compartilhado com o upload de PDF (esse
funciona no `/v1`, testado: 200 nas duas rotas). Ou seja: pra ligar transcrição no Azure precisa de
patch no fork — um client próprio dentro do `AudioTranscriptionService`, sem herdar o compartilhado.
Enquanto isso, `account.audio_transcriptions` está `true` e cada áudio recebido gera job que morre
(era a origem dos 634 jobs mortos no dead set).

### ⚠️ Contexto histórico — conta OpenAI sem crédito (achado 27/08–04/09/2026, resolvido pela migração acima)

Achado investigando erros nos logs de produção (sidekiq): **`RubyLLM::RateLimitError: You have no
credits remaining`** aparecendo repetidamente pro `Captain::Conversation::SentimentAnalysisJob`
(feature [[unattended-conversation-alert]] descoberta por acaso, sem relação com o Captain em si).
Mesma causa explica o **`Messages::AudioTranscriptionJob` com 634 jobs mortos** no Sidekiq (achado
04/09/2026, investigando o bug de vídeo/áudio quebrado — ver `.ai/fixes-log.md`): a transcrição de
áudio (`enterprise/app/services/messages/audio_transcription_service.rb`) **depende só da OpenAI**
— herda de `Llm::LegacyBaseOpenAiService`, não é multi-provedor mesmo com o roteamento de modelo do
`FeatureRouter` — e só trata explicitamente erro de credencial inválida (401), não erro de crédito
esgotado (normalmente 429), que derruba o job pra sempre no dead set em vez de reprocessar.
**Impacto real enquanto não resolver**: análise de sentimento (emoji de humor) e transcrição de
áudio recebido no WhatsApp estão silenciosamente falhando em produção. Ação: adicionar crédito na
conta OpenAI (`CAPTAIN_OPEN_AI_API_KEY`) — não investiguei se há alguma automação pra reprocessar
os jobs mortos depois disso.

### Bancada de teste

- **Inbox "Bot Lab"** (canal API, sem WhatsApp real, id **verificar antes de assumir** — já foi apagada sem querer numa limpeza e recriada, mudou de id 2→3). Horário espelhado do WhatsApp (senão `business_hours_check` mente).
- **Contato de teste** (`+5527999990003`) — cadastro real no CRM, faz o `crm_lookup` responder de verdade.
- Disparar via `rails runner`: `Captain::Assistant::AgentRunnerService.new(assistant:, conversation:, source: 'lab').generate_response(message_history:)`.
- **O Playground NÃO serve** — não passa conversa ao agente, ferramentas devolvem "Conversation not found".
- O teste que importa: não "o que ele respondeu", é "quando disse que transferiu, transferiu mesmo?" (`conv.team.present?`).

---

## Linha do tempo

**PRs #36/#37 — Captain habilitado.** Infra já pronta na VM (pgvector, 6 tabelas `captain_*`, gems `neighbor`+`pgvector`). `CAPTAIN_OPEN_AI_API_KEY` setada reaproveitando a chave da integração OpenAI da conta. Flags `captain_integration` (V1) + `captain_integration_v2` (V2) ligadas. Gating Enterprise destravado no mesmo PR (ver `premium-unlock`).

**PR #40 — Copiloto ~4x mais rápido.** `CAPTAIN_OPEN_AI_MODEL = gpt-5-mini` sem `reasoning_effort` explícito → default `medium` → centenas de tokens de raciocínio invisíveis cobrados como output, pagos a cada round-trip do loop agêntico. Fix: `reasoning_effort: minimal` em `Captain::ChatHelper#build_chat`. Medido: 7.37s→1.94s mediana, ~4,5x menos tokens. **Armadilha:** `gpt-4.1-mini` (default do resto do Chatwoot) quebra com esse param — guarda por família de modelo é obrigatória.

**PR #41 — Emoji de humor do cliente na lista.** Indicador de emoção (escala 1-5) ao lado do nome, calculado pelo Captain. Reaproveitado do "Assistente IA Mobílli" descontinuado (prompt + guards, vive em `git stash@{0}`): a marcação de recência `[MOST RECENT]`/`[RECENT]`/`[EARLIER]` e "julgue onde o cliente está AGORA". Zero código novo de ActionCable/store — reaproveita `Captain::BaseTaskService`, cache Redis nativo por `last_activity_at`, e o evento `conversation.updated` que o front já escuta. **Duas armadilhas achadas testando antes de codar:** (1) tasks do Captain usam `gpt-4.1-mini` fixo, não o `CAPTAIN_OPEN_AI_MODEL` — a lição do PR #40 não se aplica aqui; (2) cliques de menu do bot eram lidos como raiva (emoji de sirene, rótulos de botão) — prompt corrigido para nomear navegação de menu.

**PR #42 — fix do falso positivo de humor** (menu do bot lido como raiva) — ficou órfão fora da #41 por ter sido commitado depois do merge, resgatado numa PR própria.

**PRs #43/#45 — Captain aprende com conversas resolvidas.** `CaptainListener#conversation_faq_generator` já existia nativamente — destila conversa em FAQ, dedup por embedding (pgvector, cosseno < 0.3), fila `pending` pra aprovação. Achado: prompt nativo sem regra contra generalizar fato específico (vazou data de contrato de 1 cliente como FAQ geral) — endurecido numa subclasse. **🔴 Incidente:** ao criar o `CaptainInbox` pra isso funcionar, o Captain agiu em 3 conversas reais (nota, `pending`→`open`, atribuição) — o job agendado `InboxPendingConversationsResolutionJob` não passa pelo caminho de resposta que a trava cobria. Resolvido na PR #45: sem `CaptainInbox`, aprendizado vira listener aditivo (`CaptainLearningListener`), nativo fica sem vínculo algum.

**PR #46 — fechada sem merge** (mesmo escopo de #47, superada).

**PRs #47/#48 — Captain vira o bot de triagem.** BotFlow saiu do ar, Captain assumiu. Bugs achados testando de verdade (não lendo código): (1) `business_hours` singularizado errado pelo `classify`; (2) modelo confundia cenário com time; (3) bot dizia "já te conectei" sem chamar `assign_team`; (4) roteador sem `assign_team` — só promete; (5) **bot mudo ao transferir** (PR #48, ver `plan.md`).

**PRs #50/#51 — CRM e times no orquestrador.** `crm_lookup` e `business_hours_check` adicionados ao roteador principal; `available_teams` dinâmico no prompt. Revisão por outra IA encontrou: PR #51 editou `assistant.liquid`/`agent_tools` nativos direto pra ensinar cadastro de veículo — deveria ter sido um `Scenario`/guardrail (ver `plan.md`, armadilha #8).

**PR #52 — revert do fork nativo da #51**, virou o cenário "Consulta de Cadastro" (dado, testado).

**PR #53 — extração de guardrail.** O bloco estático "Team Transfer Protocol" do `assistant.liquid` (parte legítima da #50) virou o guardrail #10 (dado). Confirmado no container: bloco estático sumiu do template, só ficou a lista dinâmica de times.

**14/07/2026 — DECISÃO DE NEGÓCIO: rollback para o BotFlow.** Ver "Estado atual" acima.

**27/07/2026 — Upgrade v4.16.1: upstream unificou a escolha de modelo do Captain num roteador novo (`Llm::FeatureRouter` + `config/llm.yml`), pisando na configuração antiga.** Antes, `agent_model` (bot orquestrador) e vários serviços de IA liam `InstallationConfig CAPTAIN_OPEN_AI_MODEL` direto — hoje esse valor é **`gpt-4.1-mini`** (não mais `gpt-5-mini` do PR #40; foi trocado depois, coerente com a tabela "Por que o bot NÃO usa gpt-5-mini" do `plan.md`, que `status.md` não tinha registrado até agora). A partir da v4.16.1, `agent_model` passou a ser:
```ruby
def agent_model
  route = Llm::FeatureRouter.resolve(feature: 'assistant', account: account)
  return route[:model] if route[:source] == :account_override || account&.feature_enabled?('captain_integration_v2')
  installation_model.presence || route[:model]
end
```
Como a conta tem `captain_integration_v2` ligada, isso **ignora `CAPTAIN_OPEN_AI_MODEL` incondicionalmente** e força `Llm::FeatureRouter::CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'` — o oposto do que a medição do `plan.md` recomenda pro bot orquestrador (gpt-5.2 é modelo de raciocínio, mesmo problema do gpt-5-mini: para de chamar ferramenta). Mitigado via o escape hatch oficial do upstream (`account.captain_models`, prioridade sobre o forçamento do v2): setado em produção `captain_models['assistant'] = 'gpt-4.1-mini'`.

**⚠️ Erro cometido e corrigido no mesmo dia:** a primeira tentativa de mitigação setou `'gpt-5-mini'` (lido de cabeça do PR #40 acima, sem checar o valor real do `CAPTAIN_OPEN_AI_MODEL` em produção nem o `plan.md` atualizado). `plan.md` já documentava que `gpt-5-mini` **não é o modelo certo pro bot** (não confiável em chamar ferramenta mesmo com `reasoning_effort`) — só a `Captain::SentimentService`/tasks e a leitura do `InstallationConfig` ao vivo (`gpt-4.1-mini`) expuseram o erro. Lição: **antes de setar um override de modelo, ler o `plan.md` (fonte de verdade sobre escolha de modelo) E o valor real do `InstallationConfig`/`captain_models` em produção — não confiar num PR antigo do `status.md` sozinho, que pode estar desatualizado.**

**Achado extra, mesmo upgrade:** `Captain::Llm::ConversationFaqService` (base nativa do PRs #43/45, "aprende com conversas resolvidas") ganhou um `fallback_model: Llm::Models.default_model_for('conversation_faq_generation')` novo, que resolve pra **`gpt-5.2`** (`config/llm.yml`) — e esse `fallback_model` tem prioridade sobre `installation_model` na cadeia de resolução do `Llm::BaseAiService#setup_model`. Sem ação, a extração de FAQ (rodando em toda conversa resolvida) trocaria de `gpt-4.1-mini` pra um modelo 3x mais caro (`credit_multiplier`), silenciosamente. Mitigado da mesma forma: `captain_models['conversation_faq_generation'] = 'gpt-4.1-mini'`. Não há medição de qualidade gpt-4.1-mini vs. gpt-5.2 pra essa tarefa especificamente (diferente do caso do bot, que tem medição real) — decisão conservadora de preservar o comportamento pré-upgrade; pode valer a pena reavaliar se `gpt-5.2` melhora a qualidade das FAQs extraídas o suficiente pra justificar o custo.

**Auditoria completa dos caminhos de LLM do Captain pós-upgrade** (todos os `Llm::BaseAiService`/`Captain::BaseTaskService` que passam por `Llm::FeatureRouter`): só `assistant` (bot orquestrador + `contact_notes`/`contact_attributes`/`action_classifier`/`assistant_chat` — todos reusam a feature `'assistant'`, cobertos pelo mesmo override) e `conversation_faq_generation` mudaram de comportamento. `document_faq_generation`, `pdf_faq_generation`, `onboarding_content_generation`, `help_center_article_generation`, `copilot` continuam em `gpt-4.1-mini`/`gpt-4.1` (sem `fallback_model` novo, `installation_model` ainda vence). Tasks (`Captain::BaseTaskService` — sentimento, labels, etc.) **não usam o roteador** quando chamadas sem `feature:` (ex.: `Captain::SentimentService` passa `model: GPT_MODEL` direto) — `resolved_model` retorna o `model` explícito sem nem consultar o `Llm::FeatureRouter` nesse caso. Continuam fixas em `Llm::Config::DEFAULT_MODEL` (`gpt-4.1-mini`), inalteradas.

---

## Achados de revisão (auditoria de PRs de outra IA)

Duas PRs (#50 e #51) foram auditadas nesta sessão por terem sido escritas por uma IA diferente:
- **PR #51**: editou dois arquivos nativos (`assistant.rb`/`agent_tools` e `assistant.liquid`) pra ensinar placa/status de contrato — existia mecanismo de dado (`guardrails`/`response_guidelines`) e `Scenario` cobria o caso. Revertida (PR #52), virou cenário "Consulta de Cadastro".
- **PR #50**: parcialmente legítima (trocar `handoff` nativo por `assign_team` no roteador é justificado, sem equivalente em dado; `available_teams` dinâmico também). O bloco estático "Team Transfer Protocol" era a mesma armadilha da #51 — extraído pro guardrail #10 (PR #53).

**Regra que fica:** antes de aceitar um diff que toque `assistant.liquid` ou `agent_tools`, perguntar se não é um `Scenario`/guardrail disfarçado.
