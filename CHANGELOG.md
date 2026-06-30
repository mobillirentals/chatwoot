# Changelog

## [Não lançado]

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
