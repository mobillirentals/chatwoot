# Workflow de Desenvolvimento

> Referência rápida para fluxo de trabalho, deploy e acesso à VM.

---

## Ambiente local (Windows host)

**O Windows local NÃO tem Ruby.** Todo código Ruby roda na VM de produção ou via Docker.

### Subir o Chatwoot local

**Receita (validada em 10/09/2026 com Chrome headless):** backend no Docker, **Vite nativo no Windows**.

```bash
docker compose up -d rails             # rails + sidekiq + postgres + redis + mailhog (NÃO sobe o vite)
pnpm exec vite dev                     # em outro terminal, no host: o front (Ctrl+C para)
docker compose logs -f rails sidekiq   # acompanhar backend
docker compose restart rails sidekiq   # depois de mexer em Ruby (não recarrega sozinho)
docker compose stop                    # desliga sem apagar nada
```

Painel em `http://localhost:3000` (os assets chegam do Vite pelo proxy do Rails). Depois de muito tempo
parado o boot leva alguns minutos (`bundle install` no entrypoint); com as gems já instaladas, ~10 s.

**Por que não o Vite do container (a causa da tela branca que se repetia)**, medido em 10/09/2026:
- O container `vite` usa polling (`CHOKIDAR_USEPOLLING`) no bind mount do Windows: **53% de CPU parado**
  e ~7-8 s pra compilar cada módulo novo → `Net::ReadTimeout` no proxy do Rails.
- A checagem "o Vite está no ar?" do `vite_ruby` 3.10.2 (`ViteRuby#dev_server_running?`) usa timeout de
  **10 ms** e **guarda o resultado por 1 s**. Via `host.docker.internal` o connect leva ~5 ms (pico ~10 ms):
  basta um pico e **todo** asset daquele segundo cai no roteador do Rails (`No route matches /vite-dev/...`).
  Um import quebrado e o Vue não monta.
- A armadilha que furava a receita nativa: no `docker-compose.yaml` o `rails` tem `depends_on: vite`, então
  `docker compose up rails` subia junto o container lento, que ainda ocupava a porta 3036.

O `docker-compose.override.yml` (gitignorado, **só existe nesta máquina**) resolve os três:
`VITE_RUBY_HOST=host.docker.internal`, `VITE_RUBY_DEV_SERVER_CONNECT_TIMEOUT=1`, `depends_on: !override`
sem o `vite`, e o serviço `vite` num profile `vite-docker` (só sobe com `--profile vite-docker`). Resultado:
Vite pronto em ~4 s, painel renderizado, zero 404 e zero timeout.

⚠️ **Vários assets com 500 + WebSocket do Vite caindo, logo depois de salvar arquivos**, não é código
quebrado: é o proxy do Rails pegando o dev server no meio do full reload. Confirmação em 10 s, do host:
`curl -o /dev/null -w "%{http_code}" http://127.0.0.1:3036/vite-dev/<caminho/do/arquivo>` — 200 quer dizer
que o módulo compila e basta `Ctrl+Shift+R`; 500 aí sim é erro de transform, e o corpo da resposta diz qual.
Vale lembrar que o painel é `/app`, não a raiz.
⚠️ O caminho depois de `/vite-dev/` é **relativo a `app/javascript`** (`.../vite-dev/dashboard/helper/x.js`,
não `.../vite-dev/app/javascript/dashboard/helper/x.js`). Errar isso devolve **404 com ~19 KB de HTML** — a
página "Vite Ruby" com dica de configuração, que de relance parece erro de build e não é.

⚠️ **Commit que toca `.scss` falha aqui.** O `lint-staged` roda `scss-lint` para `*.scss`, que é um gem
Ruby — e este host não tem Ruby. O pre-commit morre com `'scss-lint' não é reconhecido`. Saídas: manter o
CSS no `<style>` do próprio `.vue` (foi o que a pesquisa dentro da conversa fez), ou commitar de dentro do
container do rails. **Nunca `--no-verify`.**

⚠️ **`pnpm dev` NÃO funciona neste host**: ele roda `overmind` com o `Procfile.dev` (rails + sidekiq +
`bin/vite`), e tudo isso precisa de Ruby.

**Specs locais:** `docker compose exec -T -e RAILS_ENV=test rails bundle exec rspec <arquivos>`. O `RAILS_ENV=test` explícito
é obrigatório (o container é `development`); o banco vira o `chatwoot_test` (o `database.yml` só troca de banco se
`POSTGRES_DATABASE` estiver setada, e não está). ⚠️ **O Redis é o mesmo do dev** e o Rails carrega o `.env` também em teste:
spec que grava chave de cache ou depende de flag do `.env` pode interferir num teste manual rodando ao mesmo tempo (ou ser
afetado por ele). Não rode specs no meio de uma simulação.

⚠️ **`docker compose logs --since` sem fuso é lido no horário LOCAL do Windows.** `--since 2026-09-10T19:00:00` vira 19h
de Brasília (3 h no futuro em UTC) e o filtro devolve **vazio** — o que parece "zero erros". Gere com
`date -u +%Y-%m-%dT%H:%M:%SZ` (com o `Z`). Mordeu em 10/09/2026: uma contagem de 404/timeout saiu zerada por isso (a
recontagem no log inteiro confirmou o zero, mas por sorte).

**Webchat local pra testar o BotFlow** (montado em 10/09/2026): inbox **"Webchat Teste"** (id 95,
conta 47 "Mobilli Dev") com o agent bot `BotFlow Local` → `http://rails:3000/webhooks/bot_flow`, e os
8 times com os nomes de produção (o `Engine#hand_off_to_human` procura pelo nome). Página de teste:
`http://localhost:3000/widget_tests?inbox_id=95`. Painel: `admin@example.com` / `Password1!` (só local).

⚠️ **Clicar em botão no webchat NÃO avança o BotFlow** (provado em 10/09/2026). No WhatsApp, tocar no botão
gera uma mensagem nova. No widget do site, o clique só grava `submitted_values` na mensagem do bot
(`Api::V1::Widget::MessagesController#update`), o que dispara `message_updated`, e o
`BotFlow::BridgeService#processable?` só aceita `message_created`. O bot fica parado no estado. Pra testar,
**digite o texto do botão** (ex.: `Atendimento`, `Ajuda plataforma`): o `match_any` do engine reconhece.

⚠️ **A bolha do widget não aparece se o SDK não foi gerado** (`/packs/js/sdk.js` dá 404). O SDK é um build
separado (`vite.lib.config.ts`) que o dev server não serve, e tem que ser gerado **dentro do container**,
porque `public/packs` é um volume do Docker (um build no host não aparece pro Rails):
`docker compose run --rm vite pnpm build:sdk`. O `run` explícito sobe o serviço mesmo estando no profile
`vite-docker`, mas esse formato ainda não foi testado. O SDK foi gerado em 10/09/2026 e fica guardado no volume, então só precisa refazer se apagar o volume `packs` ou mexer em
`app/javascript/entrypoints/sdk.js`.

### Comandos locais úteis
```bash

# Rebuild Vite (após mudanças JS)
pnpm exec vite build --mode development

# Lint JS/Vue
pnpm eslint
pnpm eslint:fix

# Lint Ruby (roda na VM)
bundle exec rubocop -a

# Testes JS
pnpm test
```

---

## VM de Produção — Chatwoot Mobílli

| Campo | Valor |
|-------|-------|
| **Host** | chat.mobillirentals.com.br |
| **IP** | <IP_DA_VM> |
| **Usuário SSH** | `chatwoot` |
| **Chave privada** | `~/.ssh/id_ed25519` (sem senha) |
| **Diretório** | `/opt/chatwoot` |
| **Docker Compose** | `docker-compose.production.yml` |

### Acesso SSH padrão
```bash
ssh -o StrictHostKeyChecking=no chatwoot@<IP_DA_VM>
```

> ⚠️⚠️ **REGRA DE OURO:** TODO comando `docker compose` na VM precisa de **`--env-file .env.production`**.
> Sem ele, `${REDIS_PASSWORD}` (e outras vars) interpolam para **vazio**. Em comandos que (re)criam
> containers (`up`, `run`), isso **recria o Redis SEM senha** → Rails/Sidekiq não autenticam → **produção cai**
> (`Redis::CommandError: ERR AUTH ... without any password configured`). Já aconteceu em 2026-07-09 rodando
> `docker compose run --rm rails db:migrate` sem o env-file. Fix: `docker compose --env-file .env.production up -d redis` + `restart rails sidekiq`.
> Prefixo correto: `docker compose --env-file .env.production -f docker-compose.production.yml <cmd>`.

### Rails runner na VM
```bash
ssh -o StrictHostKeyChecking=no chatwoot@<IP_DA_VM> \
  "cd /opt/chatwoot && docker compose --env-file .env.production -f docker-compose.production.yml exec -T rails bundle exec rails runner 'SEU_CODIGO_RUBY'"
```

### Checar sintaxe Ruby sem sobrescrever arquivo
```bash
ssh -o StrictHostKeyChecking=no chatwoot@<IP_DA_VM> \
  "cd /opt/chatwoot && docker compose -f docker-compose.production.yml exec -T rails ruby -c /dev/stdin" \
  < app/services/bot_flow/engine.rb
```

---

## Deploy — Mudanças em Produção

### Só Ruby (backend)
```bash
# Copiar arquivo para VM e reiniciar rails
scp -o StrictHostKeyChecking=no arquivo.rb chatwoot@<IP_DA_VM>:/opt/chatwoot/caminho/do/arquivo.rb
ssh -o StrictHostKeyChecking=no chatwoot@<IP_DA_VM> \
  "cd /opt/chatwoot && docker compose -f docker-compose.production.yml restart rails sidekiq"
```

> **Atenção:** O BotFlow::Engine roda em **dois containers** — `rails` (webhook) e `sidekiq` (job). Sempre reiniciar ambos após mudanças no engine.

### JS/Vue (frontend) — SÓ via CI (sem hot-patch)
⚠️ **Não existe hot-patch de frontend em produção.** Os assets JS/CSS são compilados na imagem
durante o build (Dockerfile) e o container de produção **não tem** `pnpm`/`node_modules`/vite bin
(o `docker-compose.production.yml` não tem serviço `vite`). Editar `.vue` no container não muda nada.

Fluxo correto: commit → PR → merge no `develop` → o CI (`deploy.yml`) builda a imagem (roda o vite build)
e deploya. O job `deploy` usa environment `production` com **aprovação manual** (botão "Review deployments"
no run do Actions).

---

## Git e Commits

- **Remotes:** `deploy` = fork Mobílli (`mobillirentals/chatwoot`) → **usar este no push**. `origin` = Chatwoot OSS (`chatwoot/chatwoot`) → **nunca** fazer push.
- **Padrão:** Conventional Commits — `type(scope): subject`
  - Exemplos: `feat(bot): add team routing state`, `fix(whatsapp): truncate button titles`
- **Scopes comuns:** `bot`, `assistant`, `crm`, `whatsapp`, `auth`, `ui`
- **NÃO incluir** linha `Co-Authored-By: ...` de IA nas mensagens de commit
- Commits em inglês
- ⚠️ **NUNCA usar `--no-verify`** para pular o hook de pre-commit (lint-staged / ESLint / Prettier).
  Esse lint pega justamente os erros que **quebram o build do CI** — o `vite build` falha em erro de
  ESLint/Prettier e o deploy quebra. Se o lint acusar, **corrija o código**, não bypasse.
  Validar antes de commitar: `pnpm exec eslint <arquivo>` (o host local tem node/pnpm; o container
  de produção **não** tem toolchain de frontend).
- ⚠️ **Branch nova por trabalho.** Sempre criar a branch a partir do `deploy/develop` **atualizado**
  (`git fetch deploy && git checkout -b nome deploy/develop`). **NUNCA** commitar/pushar numa branch
  que já teve PR — mesmo parecendo aberta, a PR pode ter sido mergeada e o commit vira **órfão**
  (fora do develop, sem PR aparecer). Já aconteceu (PR #16 e #17). Se orfanou: branch nova do develop
  + `git cherry-pick <sha>` + PR nova.

---

## 🔴 Corrida no CI: merges simultâneos deployam código velho

Se duas PRs mergeiam com poucos minutos (ou segundos) de diferença, os dois workflows de deploy rodam **em paralelo**. **O último a terminar sobrescreve a tag `:latest`** — mesmo que seja o build do commit mais antigo. Resultado: o `develop` fica certo, mas a imagem em produção não tem a PR mais recente. O deploy marca ✅ sucesso mesmo assim — é silencioso.

**Como detectar:** não confiar no ✅ do Actions. Depois do deploy, verificar o código DENTRO do container:
```bash
docker compose --env-file .env.production -f docker-compose.production.yml \
  exec -T rails grep -c "<algo que a PR introduziu>" <caminho/do/arquivo>
```

**Como consertar:** `gh run rerun <id-do-run-da-PR-mais-recente>` — rebuilda o commit completo e republica a `:latest`.

**Como evitar:** não mergear duas PRs em janela de poucos minutos; esperar o deploy da primeira terminar.

## Credenciais e variáveis de produção

As 56 variáveis de produção vivem em `/opt/chatwoot/.env.production` (permissão `600`, **não
versionado**). Dessas, 18 são segredos — entre eles as três chaves de
`ACTIVE_RECORD_ENCRYPTION_*`, que **não podem ser geradas de novo**: sem elas, o que está cifrado
no banco fica ilegível para sempre.

### Onde está a cópia

Desde 09/10/2026 o arquivo inteiro está guardado no **Azure Key Vault**:

| | |
|---|---|
| Cofre | `kv-mobilli-arquivo` (grupo `rg-chatwoot-prod`) |
| Segredo | `chatwoot-env-production` |
| Proteção | soft-delete + **purge protection**, retenção de 90 dias |

O mesmo cofre guarda `wa-backup-key-underchat` (chave do arquivo histórico do WhatsApp — ver
`features/historico-import/`).

### Como a VM fala com o cofre

A `chatwoot-vm` tem **identidade gerenciada** (habilitada em 09/10/2026) com permissão de
`get`/`list`/`set` nos segredos. Por isso o `.env` nunca precisa sair da VM para ser salvo ou
restaurado:

```bash
# na VM, uma vez por sessão
az login --identity --allow-no-subscriptions

# salvar o estado atual no cofre (depois de mudar alguma variável)
az keyvault secret set --vault-name kv-mobilli-arquivo   --name chatwoot-env-production --file /opt/chatwoot/.env.production

# restaurar (VM nova, ou arquivo perdido)
az keyvault secret show --vault-name kv-mobilli-arquivo   --name chatwoot-env-production --query value -o tsv > /opt/chatwoot/.env.production
chmod 600 /opt/chatwoot/.env.production
```

⚠️ **Depois de restaurar, confira o `chmod 600`** e apague qualquer cópia temporária
(`shred -u`). O arquivo já esteve em `664` — legível por qualquer usuário da VM.

⚠️ **Mudou variável na VM? Suba de novo para o cofre.** O cofre não acompanha sozinho; a cópia
envelhece em silêncio, e isso só aparece no pior momento.

### Quem tem acesso

| | |
|---|---|
| `suporte@mobillirentals.com.br` (Suporte TI) | `get`, `list`, `set`, `recover` — **conta de custódia** |
| identidade da `chatwoot-vm` | `get`, `list`, `set` |

Acesso é sempre de conta da empresa, **nunca de conta pessoal** — quando alguém sai, a custódia
não sai junto.

---

## Notas de infra

- Login como `root` na VM redireciona para `chatwoot` — normal
- Warnings de `TYPEBOT_*`, `SMTP_*`, `RubyLLM acts_as API deprecated` → normais, ignorar
- Banco de dados: PostgreSQL container (`cw_app` database), Redis container separado

---

## Seeding / Dados de teste

```bash
# Dados mínimos para verificação de features
bundle exec rails db:seed

# Dados para search/performance
bundle exec rails search:setup_test_data

# Dados ricos para uma conta específica (via Super Admin ou CLI)
bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(ID))"
```
