# Chamadas de voz pelo WhatsApp (WhatsApp Calling API)

**Estado:** ligado em produção **só na caixa de Testes** (#1, +55 27 99284-0261) em 06/10/2026, para
o usuário experimentar. Nada de código nosso — é recurso do upstream v4.18.0 que estava desligado.

## Por que não precisou de código

O Chatwoot já traz dois caminhos de voz, e a diferença importa:

| | WhatsApp Calling | Canal de Voz (Twilio) |
|---|---|---|
| quem liga | o cliente, pelo próprio WhatsApp | número de telefone comum |
| quem atende | o atendente, **no navegador** (WebRTC) | idem |
| exige | caixa `whatsapp_cloud` | conta Twilio + número com voz |
| temos? | ✅ duas caixas elegíveis | ❌ nenhum canal Twilio |

Só o primeiro serve para nós. Ele vale para **qualquer** caixa `whatsapp_cloud`, de assinatura
embutida ou de chave manual — o que não alcança as APIs de chamada é o 360dialog (provider
`default`). A caixa da ponte Baileys (#11) **não suporta**: `voice_calling_supported?` exige
`whatsapp_cloud`.

## O que foi ligado, em ordem

1. **feature `channel_voice` na conta** — era `false`. É pré-requisito duro:
   `enable_voice_calling!` levanta exceção sem ela, e o botão no painel depende de
   `isCloudFeatureEnabled(CHANNEL_VOICE)`.
2. **`enable_voice_calling!` no canal de Testes** — `POST /{phone_number_id}/settings` com
   `calling.status: ENABLED`, depois `register_callback`, e só então grava
   `calling_enabled: true`. A ordem é de propósito (comentário no modelo): se o webhook falhasse
   depois do flag, a caixa diria `voice_enabled?` sem o WABA estar assinado em `calls`.
3. **`call_icon_visibility: DEFAULT` na Meta, à mão** — ver a armadilha abaixo.

## ⚠️ O ícone de ligar: o Chatwoot não configura

`enable_voice_calling!` manda **só** `calling.status`. O campo `call_icon_visibility` ficou
`NOT_SET`, e é ele que decide se o cliente vê o botão de ligar dentro da conversa do WhatsApp.
Sem ele só funcionaria a chamada de saída (atendente → cliente); o caso que interessa — o cliente
ligar para o SAC — não apareceria, **sem nenhum erro em lugar nenhum**.

Posto à mão no número de Testes:

```
POST /v22.0/{phone_number_id}/settings
{ "calling": { "status": "ENABLED", "call_icon_visibility": "DEFAULT" } }
```

`callback_permission_status` segue `NOT_SET` — é outra coisa (pedir ao cliente permissão para
retornar a ligação) e não foi mexido.

## ⚠️ O WABA é compartilhado com o SAC

As duas caixas oficiais (+5527997756598 SAC e +5527992840261 Testes) vivem no **mesmo WABA**
(`1854862678487143`), e `subscribed_fields` é assinatura **do WABA**, não do número. Ativar voz
reescreve a assinatura que o SAC também usa.

O upstream já previu isso — `Whatsapp::WebhookSetupService#calls_enabled_on_waba?` mantém `calls`
se **qualquer** caixa irmã no mesmo WABA tiver voz ligada, justamente para uma caixa sem voz não
derrubar a assinatura da que tem. E o roteamento é por número: o `override_callback_uri` do SAC
continua apontando para a URL dele, e o nível de número tem precedência sobre o nível de app.

Verificado depois de ativar: o SAC recebeu 9 mensagens nos 10 min seguintes, zero job morto novo.

Detalhe que confunde: `GET /{waba}/subscribed_apps` **não devolve** `subscribed_fields` nem quando
pedido explicitamente — devolve só o app assinado. Não é sinal de problema; não tente diagnosticar
por aí.

## Caminho de volta

```ruby
Channel::Whatsapp.find_by(phone_number: '+5527992840261').disable_voice_calling!
```

Desliga o flag primeiro e só depois reassina o webhook (best-effort, para uma queda da Meta não
prender ninguém). A `calling.status` na Meta fica intacta de propósito. Para esconder o ícone de
novo, `call_icon_visibility: DISABLE_ALL` na mão.

## Como a chamada atravessa

`field: 'calls'` no webhook → `Enterprise::Webhooks::WhatsappEventsJob#handle_message_events`
desvia antes do caminho de mensagem → `Whatsapp::IncomingCallService`. O módulo entra por
`prepend_mod_with` no job base, e o código enterprise está carregado nesta instância (o
`update_calling_status`, que é de `enterprise/`, respondeu).

A Meta manda **duas formas** sob `field=calls`: `value.calls[]` (connect, terminate) e
`value.statuses[]` (RINGING, ACCEPTED) — é o segundo que diz que o cliente atendeu de verdade na
chamada de saída. Há mutex por `call_id`.

**WebRTC:** o áudio não passa pelo nosso servidor; o navegador do atendente fala direto. STUN é o
público do Google (`stun:stun.l.google.com:19302`, configurável por `VOICE_CALL_STUN_URLS`). **Não
há TURN configurado** — numa rede corporativa restritiva a chamada pode não completar, e esse é o
primeiro lugar a olhar se o áudio não sair.

## Estado em 06/10/2026

- conta: `channel_voice` true, `voice_recorder` true
- Testes (#1): `voice_enabled?` true, `inbound_calls_enabled?` true, Meta `ENABLED` + ícone `DEFAULT`
- SAC (#5): `voice_enabled?` false, `calling_enabled` nil — intocado
- caixa #11 (Baileys): não suporta
- `Call.count`: 0 (nada testado ainda)
- a caixa de Testes **não tem membros** — só admin vê

## 06/10/2026 — os dois testes reais

### 1º teste: a ligação saía e o Chatwoot não ficava sabendo

O usuário ligou do celular às 17:22 UTC. No WhatsApp dele: **"Ligação de voz — Não atendida"**.
No painel, *Chamadas* vazio. Depois, uma chamada de saída pelo painel: pedido de permissão
enviado, cliente aceitou, **o telefone tocou** — e mesmo assim `Call #1` ficou
`status: no_answer`, `started_at: nil`, `end_reason: agent_hangup`. A chamada nunca saiu de
"chamando": o Chatwoot não recebeu o aviso de que o cliente atendeu, e quando o atendente
desligou o widget, virou "não atendida".

**Causa:** o campo `calls` estava **desassinado no app**, no painel do Meta for Developers. São
dois níveis e os dois precisam ter `calls`:

1. **WABA** — `POST /{waba}/subscribed_apps` com `subscribed_fields`. O Chatwoot faz sozinho no
   `enable_voice_calling!`, e funcionou (`success: true`).
2. **App** — Meta for Developers → app `2441730249624550` → WhatsApp → Configuração → Webhooks →
   campos do objeto `whatsapp_business_account`. `messages` vinha marcado (por isso mensagem
   chegava); **`calls` vem desmarcado**. O usuário marcou às 14:55 local.

Não dá para ler nem marcar isso com o token que temos: `GET /{app_id}/subscriptions` exige **app
access token** (`app_id|app_secret`), e não há `FB_APP_SECRET` no `.env.production`.

### ⚠️ Pista falsa que me custou tempo

Durante o 1º teste apareceu no log do Sidekiq:

```
Inactive WhatsApp channel: unknown - +5527992840261
```

Eu li isso como "o evento da chamada chegou e foi descartado". **Não era.** Eventos de nível de
WABA (template, conta, qualidade do número) não trazem `value.metadata`, então
`WebhookChannelFinderService` devolve nil, `channel_is_inactive?` tem `return true if
channel.blank?` e o job sai pelo warning. Isso é ruído antigo e acontece sempre. O evento de
chamada **não tinha chegado** — nem existia.

Onde olhar de verdade: **log do nginx**, não o do Rails (`LOG_LEVEL=warn`, requisição não é
registrada). E atenção ao user-agent: mensagem do WhatsApp chega como `facebookexternalua`;
entrega de nível de app vem como `Webhooks/1.1 (https://fb.me/webhooks)`.

### 2º teste: funcionou nos dois sentidos

| | direção | status | duração |
|---|---|---|---|
| Call #2 | saída | completed | 21s |
| Call #3 | saída | completed | 36s |
| Call #4 | **entrada** | completed | 11s |

Zero webhook descartado. Gravação anexada nas três.

## ⚠️ A URL de callback do app é fixa no número de Testes

No painel da Meta, a *URL de callback* do app é
`https://chat.mobillirentals.com.br/webhooks/whatsapp/+5527992840261`. Tudo que a Meta entregar
no nível de app (e não pelo override por número) cai nessa URL.

Para o Testes está certo por coincidência. **No dia em que ligarem voz no SAC, isso é o primeiro
lugar a conferir**: o evento de chamada do SAC chegaria numa URL com o número do Testes, e o
Chatwoot resolve o canal pelo `value.metadata` do payload — então pode até funcionar, mas é
frágil e ninguém vai lembrar.

## Transcrição: gravava e nunca transcrevia (PR #124)

Nas três chamadas completas: áudio anexado (`audio/opus`, ~74 KB), `transcript` vazio,
`call.recording.attached?` **false**, e `Llm::SpeechToTextService.available_for?` já `true`. O
motor estava pronto e ninguém chamava.

Dois furos que se somavam, e corrigir um só não mudaria nada:

1. `upload_recording` anexava o áudio e **não enfileirava** `Voice::CallTranscriptionJob` — o
   único lugar que o enfileirava era `Voice::Provider::Twilio::RecordingAttachmentService`.
2. `Voice::CallTranscriptionService` fazia `return unless call.recording.attached?`. O Twilio
   baixa a gravação da API deles e guarda em `call.recording`; a do WhatsApp é gravada **no
   navegador do atendente** e sobe como anexo de áudio da mensagem (é de lá que o player toca),
   então `call.recording` fica vazio.

Corrigido aceitando as duas origens no serviço e enfileirando no upload só quando de fato
armazenou o blob (`'uploaded'`, não `'already_uploaded'`) — transcrição é paga por chamada e o
navegador reenvia em rede ruim.

Detalhe que evita um susto: o arquivo chega com nome `call-recording.ogg`/`.webm` e o
`fetch_audio_file` usa a extensão **do nome**, não o content-type — por isso `audio/opus` passa.

### Depois do deploy do #124

As Calls #2, #3 e #4 não serão transcritas sozinhas (o job só dispara no upload). Para preencher
retroativamente: `Voice::CallTranscriptionJob.perform_later(id)` para cada uma.


## ⚠️ Erro meu na #124, corrigido na #125

A #124 fez a transcrição aparecer e, sem querer, fez o **mesmo áudio ser transcrito duas vezes**.

O que eu não tinha visto: a gravação sobe como anexo de áudio da mensagem, e **todo anexo de áudio
já é transcrito** por um `after_create_commit` no `Attachment`. Esse caminho
(`Messages::AudioTranscriptionService`) inclusive já conhecia gravação de chamada — respeita o
"Transcrever gravações" da caixa. O áudio **nunca deixou de ser transcrito**: o texto ficava em
`attachment.meta['transcribed_text']` e só não chegava em `call.transcript`, que é o campo que a
tela mostra.

Li o sintoma ("transcript vazio") como "não transcreve" e acrescentei uma segunda transcrição.
Confirmado em produção numa chamada real de 38s: os dois campos com texto **idêntico**.

Lição: antes de ligar um job novo, procurar quem **já** processa aquele objeto. `grep` por
`after_create_commit` no modelo teria bastado.

Na #125 o upload volta a não enfileirar nada; quem enfileira o job da chamada é o caminho do anexo,
depois de guardar o texto — o que também fixa a ordem (dois jobs saindo juntos do upload poderiam
achar `meta` vazio e chamar a API ao mesmo tempo).

## Transcrição pega só parte da conversa (em aberto)

Numa chamada real de 38s com fala dos dois lados, o transcript trouxe 23 palavras — **0,6
palavra/s**, contra ~2,5–3 de uma conversa normal. A Call #8 (24s) deu 1,1 palavra/s.

**O que já foi descartado como causa:**

| | |
|---|---|
| gravação incompleta | ❌ o container OGG declara **40,44s** para a chamada de 38s (li a posição granular da última página) |
| upload truncado | ❌ 210.345 bytes no blob, íntegros |
| falta de duração no metadata | ❌ os áudios de cliente, que transcrevem bem, **também** não têm |
| idioma errado | ❌ áudio real de cliente transcreve em português fluente (2309 transcritos) |

O "Hallo, is dit mij?" e os "alô alô alô" das primeiras chamadas eram **áudio quase mudo dos
testes** — alucinação conhecida do Whisper em silêncio, não defeito do motor.

**Hipótese que sobra:** a qualidade do que o microfone do navegador captura. A pessoa do outro lado
descreveu a voz do atendente como "distante, como se tivesse falando dentro do banheiro" — reverberação
típica de microfone embutido de notebook em sala aberta. Se a voz do atendente chega abafada, o
Whisper descarta esses trechos.

`getUserMedia({ audio: true })` é o que o front usa; no Chrome isso **já liga** cancelamento de eco,
supressão de ruído e ganho automático por padrão, então tornar isso explícito provavelmente não
muda nada. O que o código realmente não faz é **equalizar os dois lados na mistura** —
`createMediaStreamSource(local)` e `(remote)` entram direto no destino, sem `GainNode`. Se um lado
está muito mais baixo, ele some.

**Próximo passo barato e decisivo, antes de mexer em código:** repetir a ligação com **fone de
ouvido com microfone** e comparar palavras/segundo. Isola hardware de software. Se melhorar, era o
microfone; se não, vale o ganho por fonte na mistura.


## Transcrição separada por quem falou (em revisão, 06/10/2026)

A transcrição mostrava texto corrido, sem dizer quem falou. Essa informação **não existe no dado**:
o modelo recebe um arquivo e devolve texto. Ela tem que vir de antes, da captura.

### O que decidiu o desenho: não há ffmpeg

`which ffmpeg` não acha nada em nenhum container. Logo, **não dá para separar canais no servidor**.
A separação acontece onde as duas fontes já existem separadas: o navegador do atendente.

O gravador passou a produzir **três trilhas** sobre o mesmo `AudioContext` — a mistura (que o
player toca) e cada lado isolado. Os lados sobem **antes** da mistura, e a ordem é proposital: o
anexo da mistura é transcrito pelo seu próprio callback, e esse caminho só se cala quando os dois
lados já estão no `Call`. Invertida a ordem, o mesmo áudio seria transcrito duas vezes. Se um lado
falhar no envio, a mistura cobre sozinha — a degradação é automática.

Os lados ficam no próprio `Call` (`has_one_attached`, sem migration), **não** como anexo da
mensagem: anexo viraria mais um player na conversa e seria transcrito sozinho. São insumo, e o
serviço os **apaga** quando termina — guardados, triplicariam o armazenamento de cada chamada sem
nunca mais serem lidos.

### O modelo teve que mudar, e não pelo motivo esperado

Os modelos **novos** de transcrição abandonaram o tempo por trecho. `gpt-4o-mini-transcribe` recusa
`verbose_json` com **400**, e o `json` vem só com `text` — testado contra o próprio recurso. Quem
tem tempos é o **whisper**, mais antigo.

Deployment `whisper` criado em `ai-mobilli-prod-eus2` (SKU **Standard** — em eastus2 o whisper não
aceita GlobalStandard, ao contrário dos outros; capacidade 3). Usado **só nas chamadas**, via
`CALL_TRANSCRIPTION_MODEL` (default `whisper`); áudio de cliente segue no `gpt-4o-mini-transcribe`.

Surpresa boa: no mesmo áudio, o whisper **ouviu o lado do atendente que o outro modelo perdeu
inteiro** — "Onde?", "Pra trás do freezer?", "Mas ele é pequeno?". Para diálogo ele é melhor.

### ⚠️ Duas armadilhas do whisper, viradas em código

**`temperature: 0.0` piora.** Nosso serviço fixava 0.0 para todo áudio. Isso **desliga o fallback
de temperatura da própria API**, que é o mecanismo que quebra os loops de repetição do whisper.
Medido no mesmo arquivo: com 0.0, **79 trechos e 189 palavras** (um repetido 66 vezes); sem,
**29 e 87**. Agora a temperatura só é fixada quando NÃO se pede segmentos — nos modelos novos, que
não têm esse fallback, 0.0 continua ajudando.

**Ele repete a última frase no silêncio final** — 66 cópias de "E aí?" num teste real. O serviço
corta repetição idêntica consecutiva acima de duas (duas ainda podem ser fala humana: "alô, alô").

**429 é esperado, não exceção:** capacidade 3 e os dois lados sobem juntos. O job reexecuta com
espera crescente.

### Alerta de conversa sem resposta disparando em chamada

Chamada entra na conversa como mensagem do cliente, o que marca `waiting_since` — e o
[[unattended-conversation-alert]] tratava a ligação como alguém sendo ignorado. O cliente que
acabou de falar no telefone recebia "Nossa equipe já viu sua mensagem e vai responder em breve", e
meia hora depois o administrador era acordado por uma conversa sem nada pendente.

Regra nova: as duas camadas que falam com o **cliente** nunca disparam por causa de chamada.
A camada interna (2) continua valendo para chamada **perdida** — alguém precisa retornar — e não
dispara para chamada **atendida**, que não deixa nada pendente. Texto do cliente depois da chamada
volta a ser espera de verdade.

### Teste local sem WhatsApp

`scripts/seed_call_transcript.rb` cria uma chamada fictícia com segmentos. Com
`CALL_AUDIO=caminho/para/gravacao.ogg` usa um arquivo real; sem ele, gera um WAV do tamanho das
falas com um bipe a cada 5 s (não há ffmpeg, então é cabeçalho e amostras cruas).

⚠️ Armadilha que custou tempo: no Windows o bind-mount do Docker **não propaga evento de arquivo**,
então o processo do Rails segue com o código velho enquanto o `rails runner` já carrega o novo.
A transcrição não aparecia na tela por isso. `docker compose restart rails`.

### Verificação

Base **116 exemplos, 12 falhas** → com a feature **141, 12**: 25 exemplos novos, nenhuma falha
nova. `rubocop` e `eslint` limpos.


## Recado de voz e ajustes do teste real (PR #127, 07/10/2026)

### A plataforma já fazia

Com "Permitir chamadas de entrada" desligado, a Meta recusava a ligação na cara do cliente. Antes
de construir, fui ver se ela resolvia — **resolve, e melhor**: `voicemail` com gatilho `REJECT`
toca um aviso e **deixa o cliente gravar um recado**, que chega na conversa como áudio comum e por
isso já é transcrito.

Isso evitou um projeto inteiro: tocar áudio DENTRO da ligação exigiria o servidor virar par WebRTC
(aceitar oferta, DTLS/SRTP, streaming de Opus). O Chatwoot não tem nada disso — toda a mídia vive
no navegador do atendente, e `accept_call(call_id, sdp_answer)` recebe o SDP de lá.

**Configuração atual (número de Testes):** `voicemail: { status: ENABLED, triggers: [REJECT],
audio: { default: { announcement_media_id: 2723739114736610 } } }`. Gatilho `TIMEOUT` (toca quando
ninguém atende em até 30 s, com as chamadas ligadas) existe e **não** foi ligado.

### ⚠️ Armadilhas do caminho

| | |
|---|---|
| formato | OGG/Opus, menos de 60 s — e **não há ffmpeg em container nenhum** |
| conversão | a chave do Azure OpenAI **também alcança o serviço de Fala**, e o TTS entrega direto em OGG/Opus. 38 vozes pt-BR. Sem recurso novo, sem conversão |
| upload | `use_case=call_voicemail_announcement`; **o multipart do HTTParty não monta arquivo** nesta versão (a Meta responde "The parameter file is required") — corpo montado à mão |
| ouvir | o áudio só sai da Meta **com o token**, que não pode ir ao navegador: endpoint próprio devolve os bytes, com carimbo de tempo na URL contra cache |

Trocar pela linha de comando: `scripts/set_call_voicemail.rb` (aceita `TEXT=` e gera a voz, ou
`AUDIO=` com arquivo pronto, ou `DISABLE=1`).

### Pedido de permissão que nunca chegava

A solicitação é **mensagem interativa de forma livre, não template**: fora da janela de 24 h a Meta
**aceita o POST e devolve wamid**, falhando a entrega depois. E como ela **não é uma mensagem do
Chatwoot**, quando o aviso de falha chega não há o que marcar — a falha é invisível por construção.
Agora recusa antes, com aviso. Mesmo critério do CSAT (`not_sent_due_to_messaging_window`).

**Consequência que vale saber:** contato que nunca escreveu, ou escreveu há mais de 24 h, e ainda
não deu permissão → **não dá nem para pedir**. Fica travado até ele mandar mensagem. O comentário
no topo do serviço fala em "opt-in template", que atravessaria a janela, mas o código manda forma
livre — pode ser saída, não foi investigado.

### Os 10 segundos até tocar

A oferta só ia à Meta depois que a coleta de candidatos ICE **terminava** (a API não aceita
trickle). Quando ela não fecha — e com **só STUN público, sem TURN**, não fecha — pagava-se o teto
de 10 s inteiro. Agora encerra no primeiro candidato público (+800 ms), ou em 3 s se só vieram
candidatos locais. **Sem TURN, rede fechada ainda pode não completar o áudio: continua em aberto.**

### Outros

- balão de voz era o único **sem hora**, e mostrava relógio de "Enviando" que nunca vira nada
- **"Atendido por"** em chamada que o agente fez: em inglês "Handled by" cobre os dois casos, em
  português não. Chave nova por direção
- atividade "aceitou a permissão" saía **em inglês**: nasce no webhook, que não aplica o idioma da
  conta. A tradução já existia
- painel de chamada **arrastável**, com limite de tela e posição guardada; alça de seis pontos
- **11 traduções** faltando nas telas em uso (de 198 no total; as outras 187 em telas de
  integração/configuração)

### ⚠️ Duas que quase passaram batido

**Concern não carregava, em silêncio.** `included do include ... end` num módulo que é
**prepended** — o bloco `included` do `ActiveSupport::Concern` **não dispara em prepend**. As ações
não existiam e a tela dava 404. E `enterprise/app/controllers/concerns/` **não está no autoload**.
Caminho certo: `enterprise/app/controllers/enterprise/api/v1/accounts/inboxes/`, com `include` no
corpo do módulo.

**A guarda da janela quebrou 7 testes, e eles estavam certos:** criavam conversas sem mensagem do
cliente. Um deles é o caso real — ligando por `contact_id`, o controller monta conversa nova, que
por definição tem janela fechada.

### Verificação

Base **196 exemplos, 12 falhas** → **218, 12**: 22 novos, nenhuma falha nova. 17 testes de front.
`rubocop` e `eslint` limpos nos arquivos tocados.


### ⚠️ Player autenticado: `<audio src>` não serve (PR #128)

O endpoint que serve o áudio estava certo e testado contra a Meta (255 KB, cabeçalho `OggS`), e
mesmo assim o player dava **401**. A requisição de um elemento de mídia é feita **pelo navegador**,
não pelo axios: ela não leva `access-token`/`client`/`uid`, e não há como fazer o elemento mandá-los.

Para qualquer binário autenticado da API: buscar com `responseType: 'blob'` e passar
`URL.createObjectURL(...)` ao player, liberando o objeto na troca e ao desmontar. Isso também
dispensa carimbo de tempo contra cache — cada busca cria um objeto novo.

`preload="none"` abre o player em `0:00 / 0:00` como se estivesse vazio; só vale onde há muitos
áudios na mesma tela.

**Por que o teste local não pegou:** com credenciais falsas da Meta, a seção nunca chegava ao
estado "Ativo" com player. Era exatamente o trecho fora do alcance do ambiente local — e o que
faltou foi desconfiar mais justo de onde não havia cobertura.


## Transcrição por locutor: as duas causas reais (PRs #129 e #130, 07/10/2026)

A primeira chamada real no SAC saiu assim: `TI: Thank you very much.` e télugo do lado do cliente.
Três problemas distintos, descobertos um a um.

### 1. Idioma (PR #129)

O whisper adivinha o idioma e erra feio em áudio curto. **Provado no mesmo arquivo:** sem
informar, detectou "english" e devolveu "Thank you very much."; com `language`, virou "Tudo bem? /
Pra gente... / Então, valeu.".

Só no caminho com segmentos. O modelo dos áudios de cliente acerta sozinho e tem 2300+
transcrições boas — mexer nele seria risco sem ganho.

### 2. ⚠️ O whisper DESCARTA o silêncio, e isso quebrava a ordem (PR #130)

**Experimento decisivo, de cinco minutos:** gerei um áudio com 9 s de silêncio seguidos de fala.
O whisper reportou o trecho em **0,00 s**.

Logo, os tempos de dois arquivos diferentes **não são comparáveis**. Quem fala depois tem silêncio
no começo do seu arquivo, o silêncio some, e a fala dele é reportada como se fosse no início —
ordenar por `start` produzia um diálogo que nunca existiu.

Solução: o navegador mede a energia de cada lado durante a gravação (`AnalyserNode`, amostra a
cada 100 ms) e manda os intervalos de fala junto. O servidor converte por **duração acumulada** —
as duas grandezas contam só fala, e os intervalos sabem onde cada pedaço aconteceu.

Detalhe que o teste revelou: na emenda entre dois intervalos o tempo significa coisas diferentes
conforme seja **fim** ou **início** de trecho; sem distinguir, uma frase que termina na emenda
apareceria começando depois de terminar.

**Confirmado em produção:** `contact: 2,6–13,6s | agent: 16,2–24,4s`, com os segmentos na ordem
certa.

### 3. Alucinação em silêncio (PR #130)

O whisper inventa texto sobre silêncio — télugo, "Thank you very much.", letra de música. Cada
trecho do `verbose_json` traz `no_speech_prob`, `avg_logprob` e `compression_ratio`: o que o
próprio modelo marca como provável silêncio, ou com assinatura de repetição, é descartado.

Isso também consertou o **lado calado aparecer "falando" no gráfico** — as faixas são desenhadas a
partir dos segmentos, então texto inventado virava barra de atividade.

### ⚠️ Vazamento acústico não é código

Telefone e computador na mesma sala: cada microfone grava as duas vozes e os arquivos **já chegam
misturados**. A separação acontece na captura; nenhum código desfaz depois. Testar com fone no
computador e o celular em outro cômodo.

### ⚠️ Antes de teorizar, recarregue a página

Duas vezes seguidas o sintoma foi código velho rodando, não defeito: primeiro o bind-mount do
Docker no Windows (processo Rails com código antigo), depois o pacote JS antigo no navegador.
Na segunda, cheguei a começar um limiar adaptativo para um problema que não existia — o corte fixo
funcionava, e um refresh resolveu. Checar o banal antes do interessante.
