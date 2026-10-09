# Contexto de Arquitetura e Decisões Técnicas

> Complementa `project_summary.md`. Referência estável — coisas que quase não mudam. Histórico vivo de cada customização fica em `features/<nome>/status.md`.

---

## Bot de triagem WhatsApp — BotFlow::Engine

**Typebot DESCONTINUADO.** O bot agora é uma máquina de estados em Ruby puro. Arquitetura, gotchas de plataforma e linha do tempo completa: **`.ai/features/bot-flow/status.md`**.

### Arquivos principais
- `app/services/bot_flow/engine.rb` — máquina de estados principal
- `app/services/bot_flow/bridge_service.rb` — bridge que aciona o engine via webhook
- `app/services/crm/client_profile_service.rb` — integração CRM (Bitrix + Asaas), cacheada. ⚠️ **DESCONTINUADA em 09/10/2026**: os serviços respondem, mas a empresa não os usa mais e não haverá integração com eles. Código mantido porque o BotFlow e o `crm_lookup` ainda o chamam.

### Webhook
- Rota: `POST /webhooks/typebot` (nome mantido por compatibilidade — ver "Typebot" abaixo)
- Acionado pelo Agent Bot do Chatwoot

### Estado da conversa
- Armazenado em `conversation.additional_attributes`: `['bot_state']` (estado da máquina), `['bot_crm']` (dados do CRM cacheados)

---

## Assistente IA Mobílli — CONGELADO

Chat interno de IA para agentes (Fases 1-3: painel Vue, `ChatService`, tools, RAG com pgvector, análise de qualidade, sugestão de KB). **Nunca foi commitado e nunca rodou em produção.**

- **Onde ele está:** só em `git stash@{0}` (`mobilli-assistant-wip`), ~43 arquivos untracked. Listar com `git show --stat "stash@{0}^3"`; ler um arquivo com `git show "stash@{0}^3:<caminho>"`.
- **Não existem** no working tree: `lib/mobilli_assistant/`, `app/javascript/dashboard/components-next/mobilli-assistant/`, tabelas `mobilli_*`. Se um doc antigo citar esses caminhos, o doc está errado.
- **Por que morreu:** o **Captain nativo** (destravado neste fork, ver `.ai/features/captain/`) entrega o mesmo — assistente/copiloto RAG com base de conhecimento em pgvector — mantido pelo upstream, sem custo de manutenção nosso. A Fase 4 (RAG custom com a gem `neighbor`) virou redundante.
- **O que foi salvo dele:** a análise de humor do cliente, portada para o Captain nativo (PR #41, prompt + lógica de recência). É o único pedaço que sobreviveu.
- **Antes de "reimplementar" algo do Assistente:** confira se o Captain já não faz. Quase sempre faz.

### Referência de rotas/arquivos planejados (nunca implementados de verdade)

Um plano antigo previa `lib/mobilli_assistant/chat_service.rb`, `lib/mobilli_assistant/tools.rb`, rotas `POST /api/v1/accounts/:id/mobilli_assistant/{chat,toggle,configure}`, coluna `accounts.mobilli_assistant_enabled`. **Nada disso existe no working tree** — é só para reconhecer se aparecer citado em algum plano antigo.

---

## Typebot (infraestrutura histórica — mantida, bot descontinuado)

O Typebot **não roda mais**: fora do `docker-compose.production.yml`, sem container na VM, imagens já removidas do disco no prune.

Sobraram só **resíduos de nomenclatura**, que funcionam e não devem ser "consertados" à toa:
- rota `post 'webhooks/typebot'` → aponta para `Webhooks::BotFlowController` (nome público mantido pra não quebrar integrações)
- params/variáveis `typebot_id` dentro do `BotFlow` (legado, ignorado pelo `BridgeService`)
- `nginx/typebot.conf` — arquivo morto

Infra antiga (se algum dia precisar): builder `bot.mobillirentals.com.br`, viewer `botviewer.mobillirentals.com.br`, banco `typebot` no mesmo PostgreSQL (`cw_app`), SSO Azure via o mesmo app registration "Chatwoot (prod)".

---

## Lixeira (Trash / Soft Delete)

Arquitetura genérica de exclusão lógica, implementada para Conversas. Detalhes completos e linha do tempo: **`.ai/features/trash/status.md`**.

---

## Enterprise Edition

O Chatwoot tem um overlay Enterprise em `enterprise/` que estende o OSS.

**Checklist ao modificar código core:**
1. Buscar arquivos relacionados em `app/` E `enterprise/` antes de editar
2. Novas features: verificar se Enterprise precisa de override ou extension point
3. Usar `prepend_mod_with` / `include_mod_with` para comportamento Enterprise-only
4. Não hardcodar comportamento de plano/instância no OSS

Gating premium destravado neste fork — ver `.ai/features/premium-unlock/status.md`.

---

## Integrações externas

| Integração | Uso |
|-----------|-----|
| ~~**Bitrix24**~~ | CRM — busca de clientes por telefone. **Descontinuado em 09/10/2026** (no ar, mas sem uso) |
| ~~**Asaas**~~ | Financeiro — dados de cobrança. **Descontinuado em 09/10/2026** (no ar, mas sem uso) |
| **Azure AD / Microsoft Entra ID** | SSO (Chatwoot + Typebot) |
| **OpenAI** | LLM do Captain |
| **WhatsApp Cloud API** | Canal principal de atendimento |
