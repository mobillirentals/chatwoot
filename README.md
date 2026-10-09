# Chatwoot — Mobílli Rentals

Plataforma de atendimento ao cliente da **Mobílli Rentals**, construída sobre o
[Chatwoot](https://github.com/chatwoot/chatwoot) e adaptada às regras de negócio da locadora.

Não é uma instalação com tema trocado: o fork carrega funcionalidades próprias que o Chatwoot não
tem — triagem automática pelo WhatsApp, chamadas de voz com transcrição, exportação de histórico
com valor probatório, lixeira com retenção, auditoria de ações sensíveis e um conjunto de ajustes
nascidos do uso diário do time de atendimento.

**Produção:** https://chat.mobillirentals.com.br

---

## O que foi construído sobre o Chatwoot

### Atendimento por WhatsApp

| | |
|---|---|
| **Triagem automática (BotFlow)** | Motor de fluxo próprio que recebe, classifica e encaminha a conversa ao time certo antes de chegar a um humano |
| **Chamadas de voz** | Ligação pelo WhatsApp direto do painel, com gravação, **transcrição separada por locutor** e recado de voz quando a chamada é recusada |
| **Modelos de mensagem** | Criar, editar e apagar modelo sem sair do Chatwoot, com as regras da Meta validadas antes do envio e prévia do balão como o cliente vê |
| **Disparo em massa por planilha** | Envio de modelo para uma lista (CSV/XLSX), com acompanhamento de entrega |
| **Verificador de números** | Serviço à parte que confirma se um número tem WhatsApp antes do disparo |
| **Ponte não oficial (Baileys)** | Canal alternativo para o número comercial, fora da API da Meta |

### Inteligência e automação

| | |
|---|---|
| **Captain (RAG nativo)** | Assistente e copiloto sobre a base de conhecimento, com FAQs destiladas de conversas já resolvidas |
| **Humor do cliente** | Emoji de emoção ao lado do nome na lista, para priorizar quem está irritado |
| **Aviso de inatividade e auto-resolve** | Fecha conversa parada, respeitando quem já tem atendente |
| **Alerta de conversa sem resposta** | Avisa antes de o cliente ficar esperando demais |

### Governança e registro

| | |
|---|---|
| **Exportação de histórico em PDF** | Transcrição completa com anexos, chamadas e **hash SHA-256 de integridade** — feita para valer como registro |
| **Auditoria** | Trilha de exportações, ações de bot e ciclo da lixeira |
| **Lixeira (soft delete)** | Exclusão reversível com retenção, hoje aplicada a conversas |
| **Resposta restrita** | Só responde quem assumiu a conversa |

### Experiência de uso

| | |
|---|---|
| **Busca dentro da conversa** | Procurar mensagem sem rolar o histórico inteiro |
| **Identidade visual** | Tela de entrada e cores do painel com a cara da casa |

---

## Stack

| Camada | Tecnologia |
|---|---|
| Backend | Ruby on Rails (API + monolito) |
| Frontend | Vue 3 (`<script setup>`) + Vite + Tailwind |
| Banco | PostgreSQL 16 + pgvector |
| Fila e cache | Redis + Sidekiq |
| Anexos | Azure Blob Storage |
| IA | Azure OpenAI (transcrição, embeddings, síntese de voz) |
| Produção | Docker Compose em VM Azure, atrás de Nginx |

---

## Arquitetura

```
GitHub (develop)
    └── GitHub Actions
            ├── build: docker/Dockerfile → ghcr.io/mobillirentals/chatwoot:latest
            └── deploy: SSH → Azure VM
                            └── Docker Compose
                                    ├── rails        API + dashboard
                                    ├── sidekiq      jobs em background
                                    ├── chatwoot-db  PostgreSQL 16 + pgvector
                                    ├── redis        cache e filas
                                    └── nginx        proxy reverso + TLS
```

Serviços auxiliares rodam ao lado, em contêineres próprios: a ponte Baileys do WhatsApp não
oficial e o verificador de números.

---

## Desenvolvimento local

**Pré-requisitos:** Docker Desktop e pnpm (`npm install -g pnpm`).

```bash
pnpm install
docker compose up
```

| Serviço | URL |
|---|---|
| Dashboard | http://localhost:3000 |
| Vite (dev server) | http://localhost:3036 |

> O contêiner `vite` é um serviço separado no compose. Se a interface não refletir mudanças em
> `.vue`, confira se ele está no ar.

### Testes e lint

```bash
pnpm test                       # frontend (vitest)
bundle exec rspec               # backend (rspec)
pnpm eslint <arquivo>           # lint do frontend
bundle exec rubocop <arquivo>   # lint do backend
```

---

## Deploy

Push em `develop` dispara o pipeline:

```bash
git push deploy develop
```

O build leva cerca de 5 minutos. Acompanhe em **Actions** no GitHub.

⚠️ **O pipeline não roda `db:migrate`.** Migration vai na mão, na VM, seguida de restart dos
contêineres. O passo a passo está em [`.agent/workflow.md`](.agent/workflow.md).

⚠️ **Dois merges seguidos disputam a tag `:latest`** e podem deployar código velho. Depois de
subir, confirme o que está rodando **dentro** do contêiner, não só no repositório.

---

## Infraestrutura

A VM foi provisionada com Terraform — os arquivos estão em [`terraform/`](terraform/).
`terraform.tfvars` e `terraform.tfstate` ficam fora do versionamento.

Na VM, em `/opt/chatwoot/`:

| Arquivo | O quê |
|---|---|
| `.env.production` | variáveis de ambiente (não versionado) |
| `docker-compose.production.yml` | stack de produção |
| `nginx/` | proxy reverso e certificados |

> O certificado TLS renova por **webroot**. O volume `/var/www/certbot` precisa continuar montado
> no Nginx — tirá-lo quebra a renovação, e o certificado já venceu uma vez por causa disso.

---

## Documentação

O diretório [`.agent/`](.agent/) é a documentação viva do projeto, escrita para quem (ou o que)
for mexer no código depois:

| | |
|---|---|
| `project_summary.md` | stack, funcionalidades e regras gerais |
| `context.md` | arquitetura das features próprias |
| `workflow.md` | deploy, acesso à VM, git |
| `current_tasks.md` | o que está em andamento |
| `fixes-log.md` | correções pontuais, com o porquê de cada uma |
| `features/<nome>/status.md` | histórico vivo de cada funcionalidade |

Vale mais que o histórico do Git para entender **por que** algo foi feito de um jeito: cada
armadilha que custou caro está registrada ali.

---

Baseado no [Chatwoot](https://github.com/chatwoot/chatwoot) — MIT License.
