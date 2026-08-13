# whatsapp-number-checker

Serviço standalone pra verificar se um número existe no WhatsApp. Hoje está **ligado** ao
Chatwoot (Settings → Integrações → "WhatsApp Number Checker", ver
`.ai/features/whatsapp-number-checker/status.md`), mas continua isolado na infra — build,
Dockerfile e sessão pareada são só deste diretório, nada aqui depende do resto do app pra
funcionar sozinho.

## Por que existe

A Meta não oferece mais (na Cloud API oficial) um jeito de checar se um número tem
WhatsApp antes de mandar mensagem — isso existia na API antiga (On-Premises,
`/v1/contacts`) e foi descontinuado. Os serviços de terceiros que fazem isso hoje
(CheckNumber.AI, Wassenger, Z-API, etc.) cobram por consulta e exigem subir sua lista
de telefones pra infra de outra empresa.

Este serviço resolve os dois pontos rodando localmente: usa o
[Baileys](https://github.com/WhiskeySockets/Baileys) (biblioteca open-source que
reimplementa o protocolo do WhatsApp Web/multi-device) pra manter uma sessão pareada
com um número de WhatsApp e consultar `onWhatsApp()` diretamente — sem mandar nada pra
fora da sua própria infra.

**Importante**: isso não é a API oficial da Meta (Cloud API). É o mesmo mecanismo do
WhatsApp Web comum — precisa de um número de telefone pareado via QR code, igual
escanear o WhatsApp Web no navegador. **Use um número separado do WABA oficial** usado
pelo Chatwoot — nunca o mesmo número/linha do Cloud API.

## Como rodar

```bash
cd whatsapp-number-checker
cp .env.example .env   # opcional: defina CHECKER_API_TOKEN se for expor a rede
docker compose up -d --build
```

O `docker-compose.yml` anexa este serviço na rede `chatwoot-develop_default` (criada pelo
`docker-compose.yaml` da raiz) — precisa o app principal já ter subido ao menos uma vez.
Isso é o que permite o container `rails` chamar `http://whatsapp-number-checker:3300` pelo
nome (ver `WHATSAPP_CHECKER_URL` no `.env` da raiz).

Na primeira vez, a sessão não está pareada. O jeito mais fácil é pela própria UI do
Chatwoot (Settings → Integrações → "WhatsApp Number Checker", mostra o QR e o status ao
vivo) — ou direto por aqui: acesse `GET /qr`, que retorna a imagem (PNG) pra escanear pelo
app do WhatsApp (Aparelhos conectados → Conectar um aparelho). **Use um número separado do
WABA oficial.** Depois de pareado, as credenciais ficam salvas em `./auth_session` (bind
mount) e sobrevivem a restart do container.

Pra checar o status a qualquer momento: `GET /health` (inclui o número conectado, se houver).

## API

### `POST /check`

```json
{ "numbers": ["+5527999990001", "5527999990002"] }
```

Resposta:

```json
{
  "checked_at": "2026-08-13T12:00:00.000Z",
  "results": [
    { "input": "+5527999990001", "exists": true, "jid": "5527999990001@s.whatsapp.net" },
    { "input": "5527999990002", "exists": false, "jid": null }
  ]
}
```

- Máximo de 50 números por requisição.
- Se `CHECKER_API_TOKEN` estiver definido no `.env`, é exigido no header
  `X-Checker-Token`.
- Retorna `503` se a sessão ainda não estiver conectada (nenhum QR pareado ainda, ou
  reconectando).

### `POST /logout`

Desloga de verdade no WhatsApp (não só localmente), apaga as credenciais salvas e já
reconecta com estado zerado — um novo QR fica disponível em `GET /qr` logo em seguida, sem
precisar reiniciar o container. Também guardado por `X-Checker-Token` quando configurado.

## Limitações conhecidas (não resolvidas de propósito, é só o essencial por enquanto)

- **Ambiguidade do 9º dígito no Brasil**: números BR podem existir no WhatsApp com ou
  sem o 9º dígito dependendo de quando a linha foi registrada. Este serviço checa
  exatamente o número recebido, sem tentar as duas variantes — um `exists: false` pode
  ser falso-negativo se o número certo for a outra variante. O Chatwoot já tem um
  normalizador pronto pra esse problema
  (`app/services/whatsapp/phone_number_normalization_service.rb`) — reaproveitar isso
  aqui é um bom próximo passo, se/quando este serviço for ligado a algo de verdade.
- **Uma sessão só, sem fila**: `sock.onWhatsApp` aceita lote (por isso o limite de 50
  por chamada em vez de 1 por 1), mas é uma sessão única — não pensado pra volume alto
  ainda. Dá pra evoluir depois (múltiplas sessões, fila) se o volume justificar.
- **Sessão pode cair de fora**: se o número pareado for desconectado manualmente pelo
  próprio WhatsApp (logout em "Aparelhos conectados", direto no celular — diferente do
  `POST /logout` deste serviço, que já trata isso), a sessão para de reconectar sozinha —
  precisa apagar o conteúdo de `auth_session/` e escanear um QR novo.

## Como usar no Chatwoot

Ligado em 3 pontos, todos consultivos (nunca bloqueiam o fluxo principal se o serviço
estiver fora do ar ou não pareado):

1. **Disparo em massa de WhatsApp** — antes de confirmar, a planilha mostra quantos
   números foram confirmados no WhatsApp.
2. **Criação manual de contato** — depois de salvar, um selo aparece no painel do
   contato assim que a checagem terminar (contato criado por mensagem recebida não passa
   por isso, só o criado manualmente).
3. **Nova conversa com número novo** — mesma checagem do item 2, já que esse fluxo cria o
   contato pelo mesmo caminho.

Configuração (Settings → Integrações → "WhatsApp Number Checker") e detalhes de decisão →
`.ai/features/whatsapp-number-checker/status.md`.

## Como remover completamente

```bash
docker compose -f whatsapp-number-checker/docker-compose.yml down -v
```

Depois, apagar a pasta `whatsapp-number-checker/` inteira, remover `WHATSAPP_CHECKER_URL`/
`WHATSAPP_CHECKER_TOKEN` do `.env` da raiz e reiniciar o `rails`. Os 3 pontos de uso acima e
a página de Integrações voltam ao normal sozinhos (a checagem é sempre condicional a
`Integrations::WhatsappNumberChecker::Client.configured?`) — nenhum deles quebra, só param
de mostrar a informação extra.
