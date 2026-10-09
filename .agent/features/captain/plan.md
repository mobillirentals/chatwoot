# Captain (IA nativo do Chatwoot) — Arquitetura

> Ver `status.md` para o estado atual (standby/ativo) e o histórico de PRs. Este arquivo é a arquitetura estável — como o bot é montado, as armadilhas conhecidas, a escolha de modelo. Não deveria mudar a cada sessão.

## Como o bot é montado (tudo isso é DADO, não código)

- **Assistente** = o roteador. Só tem `faq_lookup` e `handoff` (fixo no `Assistant#agent_tools` nativo — **ele NÃO consegue transferir para um time** sozinho).
- **Cenários** (`Scenario`) = os fluxos. Cada um tem instrução própria e **suas ferramentas**, extraídas da instrução: escrever `[assign_team](tool://assign_team)` no texto **registra a ferramenta** (`Scenario#resolve_tool_references`).
- **Guardrails / Guidelines** = regras de comportamento (jsonb, renderizadas no `assistant.liquid`).
- Editar o comportamento do bot = editar **cenários / guardrails / guidelines** no painel admin. **Não precisa de deploy.**

Nossas ferramentas próprias: `assign_team`, `crm_lookup`, `business_hours_check` — além das nativas `faq_lookup`, `resolve_conversation`, `add_label_to_conversation`.

## ⚠️ Armadilhas que já custaram caro

1. **`String#classify` SINGULARIZA o id da ferramenta.** Um id `business_hours` procuraria `BusinessHourTool`, falharia no `safe_constantize`, e a ferramenta **sumiria do assistente sem erro nenhum**. Daí o nome `business_hours_check`.
2. **Cenário NÃO é time.** O modelo confundia o handoff interno (invisível) com transferir para gente, anunciava *"quer que eu transfira pro time Horário de Atendimento?"* e nunca chegava a usar as ferramentas. Corrigido com guideline explícita.
3. **"Escrever não transfere".** O bot dizia *"já te conectei com o time"* sem chamar `assign_team` — a conversa ficava **sem time, na fila do bot**, com o cliente achando que estava sendo atendido. Guardrail: *a transferência só existe se você CHAMAR a ferramenta; chame primeiro, fale depois.*
4. **O roteador não tem `assign_team`.** Se nenhum cenário casar com *"quero falar com alguém"*, ele responde sozinho e só consegue **prometer**. Daí o cenário **"Falar com Atendente"**.
5. **O `ResponseBuilderJob` descarta a fala do bot se a conversa não estiver `pending`.** Ver seção abaixo — o bug mais grave que apareceu (PR #48).
6. **Nenhum time é 24/7.** Todos seguem o horário da inbox. O `assign_team` avisa o modelo quando o time está fechado.
7. **🔴 Tudo que estiver em `conversation.additional_attributes` o MODELO LÊ.** Ver "O prompt lê o `additional_attributes`" abaixo — a mina mais perigosa deste código.
8. **`assistant.liquid` e `agent_tools` quase sempre têm equivalente em dado.** Uma IA diferente editou os dois direto (PR #51) pra ensinar o bot a responder "qual a placa da minha moto?" — funcionava, mas `assistant.liquid` já renderiza `guardrails`/`response_guidelines` (jsonb, sem deploy) bem ao lado de onde ela escreveu, e o roteador já lista `Scenario`s pro modelo escolher. Revertido (PR #52); virou o cenário **"Consulta de Cadastro"**. **Antes de aceitar um diff que toque esses dois arquivos, pergunte se não é um `Scenario`/guardrail disfarçado** — são arquivos do upstream, cada edição neles é conflito de merge esperando a próxima sincronização.
9. **Objetos velhos em memória.** O `ResponseBuilderJob` carrega a conversa **antes** do agente rodar; uma ferramenta grava por **outra instância** da mesma linha. Quem ler `conversation.*` depois disso, dentro do mesmo job, vê o estado **de um minuto atrás**. Hoje o `complete_captain_team_handoff` dá `reload` antes de decidir.

## 🔴 O bot precisa FALAR antes de transferir (PR #48)

O `ResponseBuilderJob` só publica a fala do assistente **enquanto a conversa está `pending`**. Se uma ferramenta abre a conversa dentro do loop do agente, o job cai num ramo de handoff que **troca a resposta por uma mensagem enlatada** — e como o `assign_team` não liga a flag `captain_v2_handoff_tool_called`, **nenhum ramo casava e a resposta era descartada**.

Resultado real: cliente escreveu *"acabaram de roubar minha moto"* e **recebeu silêncio**. A transferência funcionou, mas o *"vá elaborando o B.O."* e o aviso de horário foram jogados fora.

**Desenho atual:** `assign_team` define o time e **marca** a conversa (`additional_attributes['captain_handoff_pending']`) **sem abri-la** → o job publica a fala do bot → `Enterprise::Message#complete_captain_team_handoff` dá `reload`, tira a marca e faz o `bot_handoff!`. **Fala primeiro, transfere depois.** O `reload` não é enfeite: sem ele, a marca é invisível, o `bot_handoff!` nunca roda e a conversa fica `pending` com time atribuído — cliente avisado, time escolhido, ninguém olhando.

## 🔴 O prompt lê o `additional_attributes` (a mina)

O snippet nativo `enterprise/lib/captain/prompts/snippets/conversation.liquid` faz:
```liquid
{% for attribute in conversation.additional_attributes -%}
- {{ attribute[0] }}: {{ attribute[1] }}
{% endfor -%}
```
**Qualquer chave guardada em `conversation.additional_attributes` é colada dentro do system prompt do Captain, crua, em toda mensagem.** É *nativo e intencional* (serve pra o widget web mandar navegador/referer) — o erro é nosso quando estacionamos dado lá. Aconteceu: o cache do CRM morava ali, o modelo passou a ler o perfil inteiro sem chamar `crm_lookup` e vazou uma data de contrato de um cliente específico.

**Regra:** cache de Captain vai para o **Redis** (`Redis::Alfred`), nunca para o `additional_attributes`.

## 💸 O Captain não fala de cobrança (decisão de produto)

O tipo da cobrança **não é modelado**: é adivinhado com `desc.include?('MULTA')` em cima da descrição livre do Asaas (`Crm::ClientProfileService#detect_charge_type`). Multa de rescisão e multa de trânsito voltam as duas como `'multa'`. Um humano lendo o roteiro se safava; um LLM não.

- `crm_lookup` devolve **só** nome, CPF, contrato ativo (sim/não) e moto — nunca valor/tipo de cobrança.
- Cenário Financeiro manda o cliente ver valor/data no app ou painel, e transfere pro time `financeiro` pra qualquer detalhe.
- `Crm::ClientProfileService.new(phone, include_payments: false)` pula as chamadas ao Asaas no caminho do Captain. **O BotFlow (quando ativo) continua com `include_payments: true`.**

Quando as cobranças forem modeladas de verdade (tipo em coluna, não em texto livre), dá pra devolver isso ao bot.

## 🔴 CaptainInbox: vincular um assistente à inbox liga TRÊS coisas

Criar um `CaptainInbox` (assistente ↔ inbox) não liga só "o Captain responde". Liga, de uma vez:

1. **Aprendizado** — `CaptainListener#conversation_resolved` → FAQs + notas de contato.
2. **Resposta automática ao cliente** — via `HookExecutionService`, em conversas `pending`.
3. **Job agendado de auto-resolve/handoff** — `Captain::InboxPendingConversationsResolutionJob`, disparado pelo `ConversationsResolutionSchedulerJob`, itera **`CaptainInbox.all`**, varre conversas `pending` paradas +1h, **resolve ou faz handoff sozinho**. **Não passa** pelo caminho de resposta — uma trava no `HookExecutionService` não o pega.

O item 3 já mexeu em conversas reais (nota privada, `pending`→`open`, atribuição) sem intenção. Nenhum cliente foi mensageado só porque o assistente estava sem `handoff_message` configurado — sorte, não projeto.

Agrava: `account.captain_auto_resolve_mode` tem **default `evaluated`** (ligado) quando `captain_tasks` está ativa.

| Modo | Job varredor (encerra `pending` parada +1h) | Ferramenta `resolve_conversation` |
|---|---|---|
| `disabled` | ❌ desligado | ❌ **também bloqueada** |
| `evaluated` | ✅ ativo | ✅ funciona |

O upstream acopla as duas na mesma chave — não dá pra ter só uma. A ferramenta é o que permite o bot encerrar o que ele mesmo resolveu; com o Captain dono da inbox isso é aceitável, mas é decisão consciente. O varredor manda mensagem ao cliente ao encerrar — texto em `assistant.config['resolution_message']` (traduzido/reescrito, o padrão em pt-BR do Chatwoot ficava ruim).

**Como o fork resolve hoje:** sem `CaptainInbox`, o Captain nativo fica inteiramente dormente (scheduler itera `CaptainInbox`; auto-reply exige `inbox.captain_assistant`). Quando ligado, as três coisas acima ficam ligadas — não tem meio-termo.

## Aprendizado sem responder (quando a inbox não está vinculada)

`CaptainLearningListener` (aditivo, `enterprise/app/listeners/`) gera FAQs enquanto a inbox não está vinculada ao Captain — sem interferir na resposta nativa. Quando (se) a inbox for vinculada de verdade, esse listener sai de cena sozinho (`return if inbox.captain_active?`) e o `CaptainListener` nativo assume. Único arquivo nativo tocado: `Enterprise::AsyncDispatcher#listeners` (uma linha).

`Captain::Llm::ReusableConversationFaqService` (subclasse) endurece o prompt sem tocar no `SystemPromptsService` do upstream — regra: "uma FAQ só vale se a resposta valer para QUALQUER cliente; nunca datas, valores, termos de contrato". O prompt nativo não tinha essa regra e já gerou uma FAQ com a data de devolução do contrato **de um cliente específico**.

Onde revisar: **Capitão → FAQs** lista só as aprovadas (`status: 'approved'`); pendentes em `/app/accounts/:id/captain/:assistantId/faqs/pending`.

## Captain tem TRÊS caminhos de LLM (hoje todos em `gpt-4.1-mini`)

Não existe "o modelo do Captain" — descubra por qual caminho o código passa antes de mexer em params:

| Caminho | Classe base | Fonte do modelo |
|---|---|---|
| **Bot / Copiloto** (agente V2) | `Captain::ChatHelper`, `Agentable` | InstallationConfig **`CAPTAIN_OPEN_AI_MODEL`** |
| **Tasks** (sentimento, labels, summary, reply suggestion, rewrite) | `Captain::BaseTaskService` | **`gpt-4.1-mini`, FIXO** em `Llm::Config::DEFAULT_MODEL` — **ignora** o `CAPTAIN_OPEN_AI_MODEL` |
| **Serviços de IA** (FAQ de conversa, notas de contato, article writer) | `Llm::BaseAiService` | InstallationConfig **`CAPTAIN_OPEN_AI_MODEL`** |

### Por que o bot NÃO usa gpt-5-mini (medido)

Caso medido: cliente pede a fatura, o bot precisa chamar `crm_lookup` e dizer o valor certo.

| Modelo | Tempo | Chamou a ferramenta? |
|---|---|---|
| `gpt-5-mini` (medium, default) | 21–32s | sim |
| `gpt-5-mini` + `reasoning_effort: minimal` | 2s | ❌ **NÃO** — rápido e burro, só conversa |
| **`gpt-4.1-mini`** | 7s | ✅ sim |

`gpt-5-mini` queima raciocínio invisível **a cada salto** do loop agêntico (roteador → cenário → ferramenta → resposta) e baixar `reasoning_effort` não resolve — sem raciocínio ele para de decidir usar a ferramenta, o que é pior que lento. `gpt-4.1-mini` não é modelo de raciocínio (zero overhead), ótimo em function-calling: 3x mais rápido, mesmo acerto (6/6 num teste de confiabilidade de transferência).

### Modelos de raciocínio (gpt-5 / série-o), se algum dia usados

Params vão em `Captain::ChatHelper#build_chat` via `with_params`. Sem `reasoning_effort` explícito, a OpenAI usa `medium` → centenas de tokens de raciocínio invisíveis cobrados como output — caro num loop agêntico com múltiplos round-trips. `reasoning_effort: minimal` dá ~4x mais rápido e ~4,5x mais barato.

**A guarda de modelo é obrigatória:** `reasoning_effort` **quebra** modelos não-reasoning (`Unrecognized request argument`) — e `gpt-4.1-mini` é o default. Só mandar o param pra `gpt-5`/`o1`/`o3`/`o4`. Hoje ninguém manda (a guarda em `ChatHelper` vê que o modelo atual não é reasoning) — se o modelo padrão voltar a ser gpt-5/o-series, a guarda religa sozinha.

Alavancas extras se precisar de mais velocidade: `verbosity: low` (gpt-5), ou enxugar as tools do Copiloto (cada tool call = mais um round-trip).

## Gating Enterprise (premium destravado)

Ver `.ai/features/premium-unlock/status.md` para os detalhes — resumo: `enterprise/config/premium_features.yml` e `PREMIUM_FEATURES` (frontend) esvaziados, então o Captain (feature EE) fica controlado só pela feature flag normal por conta, sem paywall e sem auto-desligamento à meia-noite.
