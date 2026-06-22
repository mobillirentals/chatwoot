# Chatwoot — Mobílli Rentals

Plataforma de atendimento ao cliente da Mobílli Rentals, baseada no [Chatwoot](https://github.com/chatwoot/chatwoot) (open source).

**Produção:** https://chat.mobillirentals.com.br

---

## Arquitetura

```
GitHub (develop)
    └── GitHub Actions (build & deploy)
            ├── Build: docker/Dockerfile → ghcr.io/mobillirentals/chatwoot:latest
            └── Deploy: SSH → Azure VM
                            └── Docker Compose
                                    ├── rails       (API + Dashboard)
                                    ├── sidekiq     (jobs em background)
                                    ├── chatwoot-db (PostgreSQL 16 + pgvector)
                                    ├── redis       (cache e filas)
                                    └── nginx       (reverse proxy + SSL)
```

---

## Deploy

Qualquer push para `develop` dispara o pipeline automaticamente:

```bash
git add .
git commit -m "sua mensagem"
git push deploy develop
```

O build leva ~5 min (com cache). Acompanhe em:
**github.com/mobillirentals/chatwoot/actions**

---

## Desenvolvimento local

### Pré-requisitos
- Docker Desktop
- pnpm (`npm install -g pnpm`)

### Subir o ambiente

```bash
pnpm install
docker compose up
```

| Serviço | URL |
|---|---|
| Dashboard Chatwoot | http://localhost:3000 |
| Vite dev server | http://localhost:3036 |

---

## Infraestrutura (Terraform)

A VM na Azure foi provisionada via Terraform. Os arquivos estão em [`terraform/`](terraform/).

```bash
cd terraform
terraform show     # ver estado atual
terraform plan     # planejar mudanças
terraform apply    # aplicar mudanças
```

> `terraform.tfvars` e `terraform.tfstate` são gitignored — ficam apenas localmente.

---

## Acesso à VM

```bash
ssh chatwoot@<IP_DA_VM>
```

> O IP e demais detalhes de acesso estão no `terraform/terraform.tfstate` (local, não versionado).

Arquivos em `/opt/chatwoot/`:
- `.env.production` — variáveis de ambiente (não versionado)
- `docker-compose.production.yml` — stack de produção
- `nginx/` — configuração do Nginx

---

## Scripts úteis

Executar na VM:
```bash
docker compose --env-file .env.production -f docker-compose.production.yml \
  run --rm rails bundle exec rails runner scripts/<arquivo>
```

| Script | Descrição |
|---|---|
| `scripts/create_admin.rb` | Cria superadmin (usar apenas na primeira vez) |
| `scripts/setup_mobilli.rb` | Cria times e configurações iniciais |
| `scripts/clear_sidekiq.rb` | Limpa filas do Sidekiq |
| `scripts/test_smtp.rb` | Testa configuração de e-mail |

---

## Variáveis de ambiente

O `.env.production` na VM contém todas as variáveis. Variáveis adicionais necessárias para este setup:

```env
POSTGRES_USER=cw_app
POSTGRES_PASSWORD=...
POSTGRES_DB=chatwoot_production
REDIS_PASSWORD=...
```

Referência completa: https://www.chatwoot.com/docs/self-hosted/deployment/docker

---

Baseado em [Chatwoot](https://github.com/chatwoot/chatwoot) — MIT License
