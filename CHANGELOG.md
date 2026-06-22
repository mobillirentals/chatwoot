# Changelog

## [Não lançado]

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
