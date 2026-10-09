# Chatwoot Mobílli — Resumo do Projeto

> **Fonte de verdade para agentes de IA.** Ler este arquivo ANTES de abrir código-fonte.
> Ordem de leitura recomendada: `project_summary.md` → `context.md` → `workflow.md` → `current_tasks.md` (índice) → `features/<nome>/status.md` da tarefa relevante → arquivos específicos da tarefa.

## O que é este projeto

Fork customizado do [Chatwoot](https://github.com/chatwoot/chatwoot) (plataforma open-source de atendimento ao cliente) para uso interno da **Mobílli Rentals**. Inclui funcionalidades proprietárias desenvolvidas sobre o Chatwoot OSS.

- **URL de produção:** https://chat.mobillirentals.com.br
- **Repositório base:** Chatwoot OSS (versão próxima ao `develop`)

## Stack principal

| Camada | Tecnologia |
|--------|-----------|
| Backend | Ruby on Rails (API + monolith) |
| Frontend | Vue 3 (Composition API + `<script setup>`) + Vite |
| CSS | Tailwind CSS (ver `tailwind.config.js` para tokens) |
| DB | PostgreSQL (`cw_app`) |
| Cache/Jobs | Redis + Sidekiq |
| Storage | Anexos no **Azure Blob** (`ACTIVE_STORAGE_SERVICE=microsoft`, conta `chatwootuh3q3d`, container `chatwoot`) — sem cota, cresce com a mídia dos clientes. O **disco da VM** (62GB) guarda Postgres/Redis/imagens Docker — esse **enche**: cada deploy empilha uma imagem, rodar `docker image prune -a` de tempos em tempos (**nunca** com `--volumes`). Ambos visíveis em `/super_admin/instance_status` (ver `archive/2026-07-misc.md`). |
| Infra | Docker Compose (produção) |
| Deploy | GitHub Actions (`.github/workflows/deploy.yml`): push no `develop` → builda `ghcr.io/mobillirentals/chatwoot:latest` → SSH na VM → `docker compose pull` + `up -d`. **NÃO roda `db:migrate`** (rodar manual na VM). Frontend `.vue` só via imagem (sem hot-patch). Ver `workflow.md`. |

## Funcionalidades customizadas (Mobílli) — visão geral

Cada uma tem sua pasta em `features/` com `plan.md` (arquitetura) e/ou `status.md` (log vivo). Este resumo é só o "o que é" — detalhes vivem lá.

1. **Bot de triagem WhatsApp = o [[bot-flow]]** (voltou à produção em 14/07/2026). O **[[captain]] está em STANDBY**, sendo refinado fora do ar. **Não presuma que o bot é o Captain.**
2. ~~**Assistente IA Mobílli**~~ — **CONGELADO, nunca foi para produção** (ver `context.md`)
3. ~~**Typebot**~~ — **REMOVIDO por completo** (ver `context.md`)
4. ~~**Integração Bitrix + Asaas**~~ — **DESCONTINUADA (09/10/2026).** Os dois sistemas continuam no ar, mas a Mobílli não os usa mais e **não haverá integração com eles**. O `Crm::ClientProfileService` segue no código e ainda é chamado pelo [[bot-flow]] e pelo `crm_lookup` do [[captain]] — não evoluir; quando houver CRM novo, é este o ponto a substituir.
5. **[[conversation-export-pdf]]** — transcrições com filtros, busca, preview real e hash de integridade
6. **[[audit-logs]]** — auditoria de exportações, ações de bot, ciclo da lixeira
7. **[[trash]]** — soft-delete genérico, hoje em Conversas
8. **[[captain]]** — Assistente/Copiloto RAG nativo (V1+V2), em standby
9. **Humor do cliente na lista** (parte de `captain`) — emoji de emoção (1-5) ao lado do nome
10. **Captain aprende com conversas resolvidas** (parte de `captain`) — FAQs destiladas, dedup por embedding
11. **[[whatsapp-bulk-dispatch]]** — disparo de WhatsApp por planilha (CSV/XLSX), completo, 7 PRs mescladas

## Estrutura de diretórios relevante

```
app/
  controllers/api/v1/accounts/   ← controllers customizados
  javascript/dashboard/
    components-next/             ← componentes novos (preferir este)
      Conversation/ConversationCard/  ← cards da lista (inclui CardSentimentEmoji)
      Campaigns/                 ← campanhas + disparo em massa (whatsapp-bulk-dispatch)
  services/
    bot_flow/                    ← BotFlow::Engine (bot de triagem)
    crm/                         ← integração CRM (Bitrix + Asaas)
    trash/                       ← serviços da lixeira (trash/restore/purge)
    conversations/exporter/      ← exportação de conversas em PDF
    whatsapp_bulk_dispatch/      ← disparo em massa por planilha
  models/concerns/trashable.rb   ← concern de soft-delete (default_scope deleted_at)
enterprise/                      ← overlay Enterprise do Chatwoot (Captain vive aqui)
lib/
  captain/                       ← task services do Captain (sentiment, labels, summary…)
  integrations/openai/openai_prompts/  ← prompts .liquid das tasks
.ai/                             ← contexto para IAs (este diretório, não commitado — gitignorado)
  features/<nome>/{plan,status}.md  ← uma pasta por customização
  fixes-log.md                  ← ajustes pequenos, sem pasta própria
  archive/                      ← histórico fechado, não precisa ler pra retomar contexto
```

> Não existem `lib/mobilli_assistant/` nem `components-next/mobilli-assistant/` — ver "Projetos descontinuados" abaixo.

## 🪦 Projetos descontinuados (não procure por eles no código)

- **Assistente IA Mobílli — CONGELADO.** Chat interno de IA para agentes (painel Vue, `ChatService`, tools, RAG com pgvector). Nunca foi commitado, nunca rodou em produção — vive só em `git stash@{0}` (`mobilli-assistant-wip`, ~43 arquivos untracked; listar com `git show --stat "stash@{0}^3"`). Morreu porque o **Captain nativo** entrega o mesmo, mantido pelo upstream. O que sobreviveu: a análise de humor do cliente, portada pro Captain (item 9 da lista acima). Antes de "reimplementar" algo do Assistente, confira se o Captain já não faz — quase sempre faz. Detalhes em `context.md`.
- **Typebot — REMOVIDO.** Substituído pelo [[bot-flow]]. Sem container na VM, imagens já removidas do disco. Resíduos de nomenclatura inofensivos (rota `webhooks/typebot`, params `typebot_id` legados) — ver `context.md`.

## Regras de idioma / estilo

- Comunicação com o usuário: **sempre em português brasileiro (pt-BR)**
- Código, variáveis, commits: **inglês** (convenção do projeto)
- Commits: Conventional Commits (`type(scope): subject`), **sem** `Co-Authored-By` de IA
- CSS: **somente Tailwind** — sem CSS custom, sem scoped, sem inline styles
- Vue: **sempre Composition API** com `<script setup>` no topo
- Front: **reaproveitar componentes/recursos do design system** antes de criar do zero (ex.: `components-next/input/Input.vue`, `Button`, `Spinner`). Preferir `components-next/` (design system novo). Verificar o que já existe (Glob/Grep) antes de escrever componente do zero.
- Não escrever specs salvo pedido explícito
- MVP first: happy path, sem defensive programming desnecessário
