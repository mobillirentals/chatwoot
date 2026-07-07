# Changelog

## [Não lançado]

## [2026-07-07] — Typebot: bot de triagem WhatsApp funcional

### Corrigido
- **`BridgeService#continue_or_restart`**: adicionado recovery automático de sessão travada — quando o Typebot retorna "Invalid message. Please, try again." (usuário digitou texto enquanto aguardava clique de botão), a sessão é encerrada e reiniciada do zero, evitando loop infinito
- **`BridgeService#send_buttons`**: removido truncamento artificial de títulos de botão (`whatsapp_truncate`) — solução correta é usar labels curtos no Typebot (≤ 20 chars UTF-16) em vez de remendos no código
- **Endpoint `sendMessage`**: corrigido de `POST /api/v1/sessions/{id}/sendMessage` (inexistente) para `POST /api/v1/sendMessage` com `sessionId` no body
- **Parsing de `created_at`**: corrigido conversão ISO8601 → timestamp (`.to_i` em string ISO retornava o ano, não Unix timestamp)
- **Idempotência**: adicionado `last_processed_message_id` em `additional_attributes` para evitar respostas duplicadas quando múltiplos webhooks chegam para a mesma mensagem
- **Janela de processamento**: aumentada de 2 para 10 minutos para tolerar atraso de entrega do WhatsApp

### Adicionado
- `app/services/typebot/bridge_service.rb`: serviço de ponte Typebot ↔ Chatwoot
- `app/jobs/typebot/process_event_job.rb`: job Sidekiq para processamento assíncrono
- `app/controllers/webhooks/typebot_controller.rb`: endpoint webhook receptor
- `docs/bot-flows/service-flow.md`: fluxo v2 otimizado (máx. 2 níveis, coleta de nome, self-service para documentação)

### Typebot — regra de labels WhatsApp
Labels de botão devem ter ≤ 20 code units UTF-16 (emoji = 2 unidades). Único label problemático identificado e corrigido no builder: `📋 Documentos e Dúvidas` → `📋 Docs e Dúvidas`.

---

## [2026-07-07] — Correções de infraestrutura e integração API

### Corrigido
- **nginx `underscores_in_headers on`** em `nginx/chatwoot.conf`: o nginx descartava silenciosamente headers com underscore (ex: `api_access_token`), bloqueando toda autenticação via API token — necessário para o bot fechar conversas e qualquer integração externa via header
- **DNS nginx dinâmico** (`resolver 127.0.0.11 valid=10s` + `set $upstream`) em `nginx/chatwoot.conf` e `nginx/typebot.conf`: evita 502 Bad Gateway após restart de containers Docker (IPs mudam)
- **`POSTGRES_USER`** em `docker-compose.production.yml`: variável corrigida para `${POSTGRES_USERNAME}`, eliminando warning a cada `docker compose` command

---

## [2026-07-07] — Backup automático do PostgreSQL

### Adicionado
- `scripts/backup-db.sh`: backup diário dos bancos `chatwoot_production` e `typebot` via `pg_dump` + gzip, com upload automático para Azure Blob Storage e retenção de 7 dias
- `scripts/setup-backup.sh`: script de setup one-shot para a VM — instala Azure CLI, cria container `chatwoot-backups` no Blob, instala o script e configura cron às 02:00

## [2026-07-06] — Typebot: bot de atendimento visual

### Adicionado
- **Typebot Builder** (`https://bot.mobillirentals.com.br`) — editor visual de fluxos de bot, self-hosted
- **Typebot Viewer** (`https://botviewer.mobillirentals.com.br`) — runtime dos bots publicados
- `docker-compose.yaml`: serviços `typebot-builder` (porta 3001) e `typebot-viewer` (porta 3002) para ambiente local
- `docker-compose.production.yml`: serviços Typebot conectados ao PostgreSQL e Redis existentes; variáveis mapeadas a partir de `TYPEBOT_*` no `.env.production`
- `nginx/typebot.conf`: virtual hosts HTTPS para `bot.` e `botviewer.mobillirentals.com.br` com Let's Encrypt (SAN compartilhada) e HSTS (`max-age=31536000; includeSubDomains`)
- `.env.typebot`: arquivo de configuração local (gitignored) com MailHog para SMTP em dev

### Infraestrutura
- Banco `typebot` criado no PostgreSQL de produção (owner: `cw_app`)
- Certificado SSL emitido via Certbot (válido até 2026-10-04)
- Migrations Prisma aplicadas automaticamente no primeiro boot (82 migrations)
- `DISABLE_SIGNUP=true` em produção — acesso restrito ao admin (`ti@mobillirentals.com.br`)

### Scripts operacionais
- `scripts/octadesk_import.rb`: migração de contatos e conversas do OctaDesk para o Chatwoot
- `scripts/create_agents.rb`: criação em lote de agentes via API

## [2026-06-30] — Microsoft Entra ID SSO

### Adicionado
- Autenticação SSO via Microsoft Entra ID (Azure AD) na página de login (`/app/login`)
- Botão "Entrar com Microsoft" usando fluxo PKCE via `omniauth-entra-id` v3
- Redis como session store (`redis-session-store`) para suportar tokens JWT grandes da Microsoft
- Configuração SSO gerenciável pelo super_admin em `?config=microsoft`: Client ID, Client Secret, Tenant ID e toggle de ativação
- Toggle `ENABLE_EMAIL_LOGIN` no super_admin (página geral) para forçar modo SSO-only
- Proteção automática: login por email nunca é desativado se nenhum SSO estiver ativo (lógica no backend)
- Fluxo de convite inteligente em modo SSO-only: ao clicar em "Accept invitation", a conta é ativada automaticamente (sem formulário de senha) e o agente é redirecionado para login via Microsoft
- Traduções PT e EN para todas as novas strings de SSO e ativação de conta

### Alterado
- `app_configs_controller.rb`: página `?config=microsoft` ampliada com campos SSO além dos campos de email channel já existentes
- `dashboard_controller.rb`: leitura de credenciais Azure via banco de dados (InstallationConfig) em vez de variáveis de ambiente
- `vueapp.html.erb`: `azureClientId` e `azureTenantId` expostos via `@global_config` em vez de `ENV`
- `PasswordEdit.vue`: detecta modo SSO-only e substitui o formulário de senha por ativação automática de conta
- `installation_config.yml`: adicionadas chaves `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`, `ENABLE_MICROSOFT_SSO_LOGIN`, `ENABLE_EMAIL_LOGIN`
- `installation_config.rb`: chaves Azure SSO adicionadas a `RESTART_REQUIRED_CONFIG_KEYS`

## [2026-06-22] — Setup inicial de produção

### Adicionado
- Pipeline CI/CD via GitHub Actions: build Docker → ghcr.io → deploy SSH na Azure VM
- `docker-compose.production.yml` com stack completo (Rails, Sidekiq, PostgreSQL, Redis, Nginx)
- Configuração Nginx com HTTPS (Let's Encrypt) para `chat.mobillirentals.com.br`
- Infraestrutura Azure provisionada via Terraform (`terraform/`)
- Scripts operacionais: criação de admin, setup de times, limpeza de Sidekiq, teste de SMTP
- Certificado SSL via Certbot (`scripts/certbot-init.sh`)

### Alterado
- `vite.config.ts`: bind em `0.0.0.0` para funcionar dentro do Docker
- `config/vite.json`: `autoBuild: false` e `host: localhost` para dev
- `docker-compose.yaml`: porta Postgres mapeada para 5433 (evitar conflito local), volume `pnpm_store`
- `docker/dockerfiles/vite.Dockerfile`: instalação de npm/pnpm garantida na imagem

### Removido
- Workflows upstream do Chatwoot (CI/CD deles não se aplica a este fork)
- `docker-compose.production.yaml` (substituído por `.yml`)
- `docker-compose.test.yaml` (não utilizado)
- Scripts antigos em `script/` movidos para `scripts/`
