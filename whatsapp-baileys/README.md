# Ponte WhatsApp Baileys

Liga um número de WhatsApp **pareado por QR code** (protocolo do WhatsApp Web, via
[Baileys](https://github.com/WhiskeySockets/Baileys)) a uma caixa do Chatwoot com
`provider: 'baileys'`.

Serve para número que não está na API oficial da Meta. A caixa fica sendo WhatsApp de verdade no
painel, então BotFlow, CSAT, verificador de número e relatórios por canal funcionam nela.

## ⚠️ Antes de usar

Baileys é engenharia reversa do WhatsApp Web e **contraria os termos da Meta**. O número pode ser
banido, e não há recurso nem suporte. Em troca, não há janela de 24h nem template aprovado — que é
exatamente o uso que mais queima número.

**Use em número secundário.** Nunca no principal da operação.

Um número vive em um lugar só: um número que está na Cloud API **não** pode ser pareado aqui.

## Por que é separado do `whatsapp-number-checker`

Os dois rodam Baileys, mas são **números e sessões diferentes**, em portas e pastas diferentes de
propósito:

| | porta | pasta da sessão | papel |
|---|---|---|---|
| `whatsapp-number-checker` | 3300 | sua `auth_session/` | pergunta se um número tem WhatsApp |
| `whatsapp-baileys` (este) | 3400 | sua `auth_session/` | recebe e envia mensagem de atendimento |

Duas conexões sobre a **mesma** credencial se derrubam em loop — nunca compartilhe `AUTH_DIR`. E uma
falha aqui não pode levar embora a verificação de números, que já roda em produção.

## Subir

```bash
cp .env.example .env     # gere BRIDGE_TOKEN e CHATWOOT_WEBHOOK_TOKEN (openssl rand -hex 24)
docker compose -f whatsapp-baileys/docker-compose.yml up -d --build
```

Precisa do compose principal já ter subido alguma vez, para a rede
`chatwoot-develop_default` existir.

## Parear o número

Pelo painel: **Configurações → Caixas de Entrada → Adicionar → WhatsApp → "WhatsApp por QR code"**.
A tela mostra o QR e cria a caixa sozinha quando o número parear. Para isso, as três configurações
da ponte (`BAILEYS_BRIDGE_URL`, `BAILEYS_BRIDGE_TOKEN`, `BAILEYS_BRIDGE_WEBHOOK_TOKEN`) precisam
estar preenchidas nas configurações da instalação — o navegador não alcança a ponte, quem fala com
ela é o Rails.

Na mão, sem o painel: `POST /sessions` com `{"id": "<número só dígitos>"}` e depois abra
<http://localhost:3400/sessions/SEUNUMERO/qr>. Escaneie com o aparelho do número:
**WhatsApp → Configurações → Aparelhos conectados → Conectar aparelho**.

Confirme com `GET /health` — `whatsapp_connection` deve virar `connected` e `whatsapp_number` tem de
ser o número esperado.

A sessão fica em `auth_session/` (bind mount) e sobrevive a restart. Perder essa pasta obriga a
escanear de novo.

## Criar a caixa no Chatwoot

O formulário do painel só oferece os provedores oficiais, então a caixa se cria por console —
**depois** do pareamento, porque a validação confere no `/health` se o número pareado é o mesmo da
caixa e se recusa a salvar apontando para a sessão errada.

```ruby
Channel::Whatsapp.create!(
  account: Account.first,
  phone_number: '+5527988982141',
  provider: 'baileys',
  provider_config: {
    'bridge_url' => 'http://whatsapp-baileys:3400',
    'bridge_token' => '<BRIDGE_TOKEN do .env>',
    'webhook_verify_token' => '<CHATWOOT_WEBHOOK_TOKEN do .env>'
  }
)
```

Os dois tokens têm de ser **iguais** aos do `.env`: o `bridge_token` é o que o Rails apresenta para
mandar mensagem, e o `webhook_verify_token` é o que a ponte apresenta para entregar mensagem
recebida. Sem o segundo, a rota de webhook recusa tudo — ela é pública e, fora da API oficial, não
há assinatura da Meta para conferir.

## Endpoints

| | |
|---|---|
| `GET /health` | estado de todas as sessões |
| `POST /sessions` | abre (ou reaproveita) a sessão de um número |
| `GET /sessions/:id/health` | estado da sessão e número pareado (o Rails usa na validação da caixa) |
| `GET /sessions/:id/qr` | QR em PNG, ou `?format=text` para o painel desenhar |
| `POST /sessions/:id/send` | `{ to, text, quoted_id? }` — `quoted_id` faz a mensagem chegar citada |
| `POST /sessions/:id/read` | `{ to }` — devolve o visto-azul ao cliente |
| `POST /sessions/:id/presence` | `{ to, state }` — `composing` vira "digitando..." |
| `POST /sessions/:id/logout` | desloga de verdade, limpa a sessão e já oferece QR novo |

A ponte entrega ao Chatwoot em três formatos, todos que o serviço base já entende: `messages`
(mensagem do cliente), `message_echoes` (mensagem que saiu pelo celular, fora do painel) e
`statuses` (recibo de entrega e leitura). Resposta citada viaja nos dois sentidos: ao receber, o
`stanzaId` do Baileys vira `context.id`, que é o mesmo campo que a Meta manda; ao enviar, o
`quoted_id` casa com a mensagem guardada.

`/send` e `/logout` exigem o header `X-Bridge-Token`. Sem `BRIDGE_TOKEN` configurado o serviço não
sobe: esta ponte **envia mensagem em nome da empresa**, e um endpoint aberto deixaria qualquer um na
rede mandar WhatsApp para qualquer número.

## LID: por que existe o `identidades.json`

O WhatsApp está trocando o identificador do contato por **LID** (`<id>@lid`), que **não contém o
telefone**. Nas mensagens que o cliente manda, o Baileys 6.7 entrega o número ao lado (`senderPn`);
nas que **saem** daqui — e nos recibos delas — a chave traz só o LID. E a versão instalada não expõe
tradutor de LID para número.

Então a ponte aprende por dois caminhos que se completam:

| aprende | quando |
|---|---|
| `LID → número` | o cliente escreve (LID e número vêm juntos) |
| `id da mensagem → número` | no envio, porque o número veio no próprio pedido |

Isso vive em `auth_session/identidades.json`, ao lado da sessão. **Não é opcional:** na primeira
versão ficava só em memória, e o primeiro eco testado depois de um rebuild foi descartado por LID
desconhecido. Deploy reinicia.

O limite que resta: o eco de uma conversa cujo cliente **nunca** escreveu para este número não
resolve o destinatário, e o log diz isso explicitamente em vez de falhar calado.

## O que ainda não faz

Só **texto**, nos dois sentidos. Fora desta rodada:

- mídia (imagem, documento, áudio) — o envio recusa o anexo com erro visível em vez de mandar só o
  texto e deixar o agente achar que a foto foi;
- grupo e transmissão, ignorados ao receber — a caixa é de atendimento um-a-um.

Citar exige ter a mensagem original guardada em memória (até 500 por sessão). Quando ela não está
em mãos — reinício, ou mensagem mais antiga que isso — a mensagem **vai sem a citação** em vez de
falhar: chegar sem citação é melhor do que não chegar.
