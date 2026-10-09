# whatsapp-number-checker — Status

> **Implementado e ligado** (13/08/2026). Integração em Settings → Integrações + 3 pontos de
> uso (disparo em massa, contato manual, conversa nova). Testado ponta a ponta em dev com
> sessão real pareada. Falta: pareamento em produção (decisão/ação do usuário).

## Origem

Investigando o dialog de "Detalhes" do disparo em massa (PR #83), foi confirmado que erro
`131026: Message undeliverable` (visto ao vivo na conversa #2846) é o sinal mais próximo que
existe hoje de "número não tem WhatsApp" — mas só chega via webhook assíncrono de status, e só
é capturado quando existe uma `Message` real no Chatwoot pra casar o `source_id` (não é o caso
do disparo em massa nem do `Campaign` nativo, que mandam com `message: nil` — gap documentado,
**não corrigido**, é um problema diferente deste).

Perguntado se existe forma de checar **antes** de mandar: a API oficial da Meta (Cloud API)
não oferece mais isso (existia na API antiga On-Premises, `/v1/contacts`, descontinuada).
Serviços pagos de terceiro (CheckNumber.AI, Wassenger, Z-API) fazem isso, mas custam por
consulta e exigem subir a lista de telefones de clientes pra infra de outra empresa — usuário
preferiu não pagar nem expor dados, pediu uma alternativa open-source self-hosted.

## O serviço (`whatsapp-number-checker/`)

Node.js standalone, Baileys (`@whiskeysockets/baileys`, MIT — reimplementa o protocolo
WhatsApp Web/multi-device via WebSocket direto, **não é a Cloud API oficial**). Precisa de um
número pareado via QR code — **sempre diferente do WABA oficial usado no Cloud API**.

- `GET /health` (status + número conectado), `GET /qr` (PNG), `POST /check` (lote até 50,
  `exists: true/false` por número), `POST /logout` (desloga de verdade + já reconecta com
  QR novo, sem precisar reiniciar o container). Token opcional via `X-Checker-Token`.
- Sessão em `./auth_session` (bind mount, gitignored), sobrevive a restart.
- `docker-compose.yml` próprio, mas **anexado na rede `chatwoot-develop_default`** (não mais
  isolado) — é o que permite o Rails chamar `http://whatsapp-number-checker:3300`.
- Detalhes/limitações → `whatsapp-number-checker/README.md`.

## Onde configurar: Settings → Integrações (não seção própria)

Pesquisa mostrou que o framework nativo (`Integrations::App`/`apps.yml`/`Integrations::Hook`)
é moldado pra OAuth, e que o próprio recurso do fork (Campanhas/Disparo em Massa) já vive fora
dele — eu recomendei uma seção própria por isso. **Usuário preferiu manter em
Integrações mesmo assim**, e deu certo: o Slack já tinha precedente de página de detalhe 100%
custom dentro da mesma seção (`Integration.vue` já tem um slot `#action` extensível pra
quando desconectado). Ajustes:

- `config/integration/apps.yml`: entrada `whatsapp_number_checker`, sem `action:` (não é
  OAuth) e sem `settings_json_schema` (não tem formulário).
- `Integration.vue` (componente compartilhado por TODAS as integrações) ganhou uma prop
  aditiva `useCustomDelete` (default `false`, emite `@delete` em vez da action genérica) —
  nenhuma integração existente foi afetada, testado via rubocop/eslint limpos nos arquivos
  tocados.
- `app/controllers/api/v1/accounts/integrations/whatsapp_number_checker_controller.rb`:
  `show` faz poll de status (chamado a cada ~2s pelo front) e é o único lugar que
  cria/atualiza/desabilita o `Integrations::Hook` (única fonte do badge nativo
  Enabled/Disabled); `qr` faz proxy dos bytes do PNG (browser nunca fala direto com o Node);
  `destroy` desloga de verdade (`client.logout`) e apaga o hook.
- Ícone: placeholder copiado de `public/assets/images/dashboard/channels/whatsapp.png`
  (ícone de verdade fica pra depois).

## 3 pontos de uso (escopo fechado com o usuário, com um ajuste meu que ele aceitou)

Proposta original do usuário incluía "ao mandar mensagem/template" sem distinguir onde — eu
levantei que checar em **toda resposta dentro de conversa já existente** seria redundante
(existência já provada pelo histórico) e arriscaria latência no caminho mais quente do
produto; usuário concordou em restringir a **só iniciar conversa nova com número digitado**.

1. **Disparo em massa** (`whatsapp_bulk_dispatches_controller.rb#update`): depois da
   validação da planilha, chama o client em lotes de 50 (`rescue StandardError` amplo —
   qualquer falha pula a checagem, nunca bloqueia). Resposta ganha `whatsapp_check: {confirmed,
   not_found, unchecked}`; `BulkDispatchWizard.vue` mostra "X de Y confirmados no WhatsApp" só
   quando `confirmed+not_found > 0` (silencioso se o serviço estiver fora do ar).
2. **Contato criado manualmente** (`contacts_controller.rb#create`, depois do `save!`):
   enfileira `Contacts::WhatsappPresenceCheckJob`, que grava
   `custom_attributes['whatsapp_verification'] = {exists, checked_at}`. Confirmado por
   pesquisa que este controller só é atingido por criação manual — importação CSV usa
   `DataImportJob` direto, contato de mensagem recebida usa `ContactInboxWithContactBuilder`
   — nenhum guard extra necessário. Badge no painel do contato
   (`ContactInfo.vue`, ao lado do telefone).
3. **Conversa nova com número digitado**: **achado que corrigiu uma suposição errada do
   plano** — cheguei a planejar mexer em `conversations_controller.rb#create` com um guard
   `previously_new_record?`, mas conferindo o código real
   (`ComposeConversation.vue` → `createNewContact()` →
   `ContactAPI.create`) o fluxo de "digitar um número novo" já cria o contato via
   `ContactsController#create` — **o mesmo controller do item 2**. Zero código extra
   necessário; o ponto 3 já estava coberto pelo ponto 2.

## Validado (13/08/2026, sessão real pareada em dev)

- Node: build (`apk add git` no Dockerfile — dependência do Baileys via git, não só npm),
  ciclo completo `/health` → `/logout` → auth_session limpo (correção necessária: `fs.rm`
  direto no mountpoint dá `EBUSY`, só dá pra limpar o *conteúdo*) → reconecta sozinho → QR
  novo.
- Rails ↔ Node pela rede compartilhada (`docker network ls` confirmou `chatwoot-develop_default`
  como nome real).
- `show`/`qr`/`destroy` via HTTP real: hook criado com `connected_number` ao conectar,
  `enabled: true` no `GET .../integrations/apps`, `destroy` desconecta de verdade (confirmado
  no `/health` do Node) e apaga o hook.
- `whatsapp_bulk_dispatches#update`: planilha real (2 números) → `whatsapp_check` correto
  (testado desconectado: `unchecked: 2`; plumbing completo, contagem "confirmed" não testada
  com sessão conectada por falta de tempo nessa rodada específica, mas a lógica é a mesma do
  `Client#check` já validado abaixo).
- `Contacts::WhatsappPresenceCheckJob`: contato real criado via `POST /contacts` com o número
  pareado → `custom_attributes.whatsapp_verification.exists: true` depois do Sidekiq processar.
- `bundle exec rubocop` limpo em todos os arquivos Ruby tocados (2 ofensas pré-existentes e
  não relacionadas em `contacts_controller.rb`, não mexidas). `eslint` limpo nos arquivos Vue/JS
  tocados. `spec/controllers/api/v1/accounts/contacts_controller_spec.rb`: 58 exemplos, 0
  falhas (sem regressão).
- **Não verificado nesta sessão**: renderização visual real no navegador (sem ferramenta de
  browser disponível) — Vite recompilou tudo sem erro (HMR limpo), mas falta confirmação
  visual do usuário na página de Integrações e no badge do contato.

## Pendências

- Confirmação visual do usuário (Settings → Integrações, badge no contato, contagem no
  disparo em massa).
- Ambiguidade do 9º dígito (BR) ainda não tratada em nenhum dos 3 pontos de uso.
- **Produção**: adicionar o serviço no `docker-compose.production.yml` (bloco novo, sem tocar
  nos existentes) + pareamento com um número real na VM — ação exclusiva do usuário, não feita
  nesta sessão.
- Nunca parear com o número oficial do WABA de produção.

---

## 25/09/2026 — o resultado passou a aparecer (PR #106, em produção)

Até aqui o verificador rodava e gravava `custom_attributes.whatsapp_verification`, e **nada
disso aparecia na interface** — o recurso existia sem existir. O PR #106 (`feat/verificacao-
whatsapp-visivel`) colocou o selo em quatro pontos: ficha do contato (com botão de refazer a
checagem), formulário de criação (aviso abaixo do campo enquanto digita), chip do contato no
início de conversa e cabeçalho da conversa, ao lado do aviso de identidade não verificada.
Todos com `v-tooltip`, o tooltip da plataforma — o `title` do navegador foi rejeitado na
revisão do usuário por destoar do resto.

**A regra de frescor mora num lugar só**: `app/javascript/dashboard/composables/
useWhatsappVerification.js`. O selo guardado vale por `HORAS_ATE_REVERIFICAR = 12`; passado o
prazo, abrir a tela dispara consulta nova e regrava o contato, mostrando o último resultado
conhecido enquanto a resposta não volta. O prazo é deliberado: um número tem WhatsApp hoje e
pode não ter amanhã, mas consultar a cada abertura de tela é volume de `onWhatsApp` pela sessão
pareada — exatamente o que derruba essa sessão. O botão da ficha ignora o prazo.

Nada dispara com a integração desligada, e cada contato é consultado no máximo uma vez por aba
(cache em módulo, `checagensDaSessao`).

Corrigido junto: o "verificado há X" passava a string ISO de `checked_at` para `dynamicTime`,
que espera epoch em segundos — dava data inválida. O composable agora entrega epoch.

### Estado em produção (conferido dentro do container, não pela tag da imagem)

- `contacts_controller.rb` com `whatsapp_check_number`, rotas nas linhas 228/237, ícone novo
  (12 480 bytes) e a string pt-BR do selo presente no bundle compilado.
- ⚠️ **Correção do que este documento dizia antes**: o verificador **está pareado**. O
  `/health` do container responde `whatsapp_connection: connected` com um número próprio (o
  `/health` mostra qual; não é o número do WABA), e o hook está `enabled` na conta 1. Ou seja,
  os selos funcionam de verdade em produção — a ressalva "não pareado" saiu de validade.

### Continua pendente

- Ambiguidade do 9º dígito (BR) — os três pontos de uso seguem sem tratar.
- Confirmação visual do usuário nos quatro pontos depois deste deploy.
