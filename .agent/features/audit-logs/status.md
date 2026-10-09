# Logs de Auditoria — Status

> **Completo e estável.** Logs corporativos habilitados no self-hosted (feature Enterprise, destravada — ver `.ai/features/premium-unlock/status.md`).

## Como funciona

- **PR #29**: removido `audit_logs` de `enterprise/config/premium_features.yml` — sem isso, o `Internal::ReconcilePlanConfigService` (job 00:00 UTC) desligava a feature toda meia-noite em plano `community`. Habilitado por conta via `Account.find_each { |a| a.enable_features!(:audit_logs) }`.
- **PR #30**: rótulos de `export_conversations`/`agentbot` (create/update/destroy) no `auditlogHelper.js` (evita linhas em branco no painel); controller de contatos passa a gravar `user_id` + `remote_address` no log de exportação. 17 registros antigos incompletos (sem IP/usuário) foram removidos do banco.
