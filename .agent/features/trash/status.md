# Lixeira / Soft Delete — Status

> **Completo e estável, não iterado há semanas.** Arquitetura genérica de exclusão lógica, implementada inicialmente para Conversas.

## Como funciona

- `app/models/concerns/trashable.rb` — concern genérico: `default_scope { where(deleted_at: nil) }` filtra registros excluídos de queries normais. Listar a lixeira usa `unscope(where: :deleted_at)` (não `unscoped` — isso vazava a lixeira entre contas, corrigido).
- `app/services/trash/` — `TrashService` (marca `deleted_at`, audita), `RestoreService` (limpa `deleted_at`, audita), `PurgeService` (remove fisicamente, dedupe de e-mail IMAP, audita).
- `app/jobs/trash/cleanup_job.rb` — diário via `schedule.yml` às 02:00 UTC, expurga fisicamente o que está na lixeira há +30 dias.
- UI em **Configurações → Lixeira** (`/settings/trash`) — só lista + restaura. **Sem exclusão definitiva manual na interface nem na API pública** — só via console ou pelo cron de 30 dias (decisão de segurança/integridade).
- Prévia de mensagens na lixeira: endpoint dedicado `GET /trash/:id/messages` (a conversa deletada some do `default_scope`, reusa o jbuilder de mensagens via `.trashed` + `MessageFinder`).

## Linha do tempo (PRs #31–#34)

- **PR #31/#32**: trouxe a lixeira pro `develop` + hardening — `unscope` no lugar de `unscoped`, jbuilder guarda `nil` de contact/inbox, dedupe de e-mail no purge, rótulos de auditoria.
- **PR #33**: ação "olho" abre a conversa deletada no `ConversationPreviewModal` via endpoint dedicado.
- **PR #34**: 1 log por exclusão permanente (era 3 — `purge` + 2 `destroy` genéricos); corrige paginação (meta snake_case→camelCase).

**⚠️ Gotcha reforçado:** CI não roda migrations — a migration da lixeira subiu sem rodar e o `default_scope` derrubou toda consulta de conversa até `db:migrate` manual na VM.

**Teste de purge em produção**: conversa de 37 msgs removida em ~1s, audit `purge` gerado, cascade OK.
