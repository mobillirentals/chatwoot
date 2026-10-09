# WhatsApp não oficial (ponte Baileys) — Status

> Número de WhatsApp fora da API da Meta, pareado por QR code, atendido como caixa normal do
> Chatwoot. Serviço Node em `whatsapp-baileys/` + provider `baileys` no canal WhatsApp.

## ⚠️ Antes de qualquer coisa

Baileys é **engenharia reversa do WhatsApp Web** e contraria os termos da Meta: **o número pode ser
banido, sem recurso**. Número secundário, nunca o principal. Um número que está na Cloud API **não**
pode ser pareado aqui — um número vive em um lugar só.

## Estado: EM PRODUÇÃO desde 06/10/2026 (PRs #121, #122 e #123)

**Caixa #11 "Whatsapp Comercial"**, +55 27 98898-2141, sessão `s-a6060ec9-...`. Validada com texto,
citação nos dois sentidos, mídia e recibos de leitura. Isenta dos alertas de conversa sem resposta
(`UNATTENDED_ALERT_EXCLUDED_INBOX_IDS = 11`). Ponte em `/opt/chatwoot/whatsapp-baileys` na VM, sem
porta publicada no host.

### Sem modelo aprovado e sem janela de 24h (PR #123)

Modelo é mecanismo da API oficial — a Meta aprova o texto e ele vale fora da janela. Num número
pareado por QR code não existe nem aprovação nem janela, e a tela de nova conversa oferecia **só** o
seletor de modelos, com "Nenhum modelo encontrado": não dava para acionar cliente nessas caixas.

💡 **O compose perguntava "é WhatsApp?" onde o que importa é "precisa de modelo aprovado?"** — eram
a mesma coisa até existir caixa de WhatsApp fora da API oficial. A prop virou
`requiresWhatsappTemplate` e é falsa no provider `baileys`.

⚠️ **Eram TRÊS lugares com a mesma pergunta errada**, não um: o seletor de modelos, o
`shouldShowMessageEditor` e a `validationRules` que dispensa a mensagem. Corrigir só o primeiro
deixou a tela com os botões de emoji e assinatura e **sem campo para escrever** — o usuário testou e
viu. Ao mudar um conceito, `grep` em todos os usos antes de mandar testar.

A janela de 24h já estava resolvida no backend desde o #121 (`MessageWindowService` isenta baileys),
e o painel decide pelo `can_reply` que vem de lá — então nenhum aviso de "janela encerrada" aparece.

📎 O markdown do editor chega certo: `**negrito**` vira `*negrito*` no `outgoing_content`, que é o
formato do WhatsApp. O Chatwoot já fazia essa conversão.

### A caixa Comercial responde e encerra sozinha (06/10/2026)

O número ficou como **aviso de desativação**: quem escrever recebe o redirecionamento para o SAC
(27 99775-6598) e para vendas (92 2398-1266), e a conversa se encerra sozinha depois de 1h.

Montado **só com configuração nativa**, para qualquer pessoa desligar sem código:

| o quê | onde | como desativar |
|---|---|---|
| a resposta | saudação da caixa (`greeting_enabled`) | toggle "Ativar saudação do canal", na própria caixa |
| o encerramento | automação #2, com espera de 1h | liga/desliga em Configurações → Automação |
| o atraso funcionar | feature `delayed_automations` na conta | — |

⚠️ **A atribuição automática da caixa precisa ficar DESLIGADA.** Ela vem ligada por padrão e
distribui as conversas entre os membros por rodízio — numa caixa de número desativado isso acionava
atendentes para conversas que ninguém precisa atender (a Yasmin recebeu uma logo no primeiro dia).
Não é a política "Atribuição - WhatsApp Produção", que é só da caixa 5: é o rodízio nativo da
própria caixa (`enable_auto_assignment`). Desligado em 06/10/2026; os membros foram mantidos, então
quem quiser olhar a caixa consegue, mas não recebe nada automaticamente.

💡 **A saudação dispara na primeira mensagem de cada conversa**, não a cada mensagem: quem mandar
três seguidas recebe uma resposta só. Automação em `message_created` responderia às três.

⚠️ **O pedido original era "não encerrar se um agente assumiu"** — e isso NÃO é o que está no ar.
A primeira versão, criada por console, tinha `assignee_id is_not_present` e atendia exatamente isso
(provado nos quatro estados). Mas a tela de automação **não sabe representar essa condição**: ela
exibia a caixa em branco e o status errado, e quem clicasse em "Atualizar" salvaria por cima,
transformando a regra numa que vale para **todas as caixas**. O usuário preferiu, com razão, uma
regra que a tela mostra corretamente e que qualquer um edita.

O que está no ar conta tempo **no status**: encerra o que ficar 1h em aberto na caixa, inclusive o
que um agente assumiu e deixou aberto. Para segurar, o agente marca como **pendente** ou **adia** —
aí a contagem para. Validado: pega Comercial aberta, ignora pendente/resolvida, e **ignora o SAC**.

⚠️ **Duas limitações da automação com espera**, para não se perder de novo:
1. Em eventos de conversa, só `status` e `inbox_id` são aceitos como condição — atributo mutável
   quebraria o controle de episódios (`execution_delay_supported_event`). `message_created` é isento
   dessa regra, e foi por aí que a primeira versão conseguiu usar `assignee_id`.
2. `is_not_present` existe no backend (`lib/filters/filter_keys.yml`) mas **não** na lista de
   operadores da interface — dá para gravar por console, mas a tela não exibe nem preserva.

💡 A conversa que já estava aberta antes da regra existir **não entra**: o evento é
`conversation_updated`, então só vale a partir da próxima atividade nela.

💡 **A feature ligada no servidor não aparece na hora:** o painel carrega as features no boot, e a
opção "Executar após um período de espera" só surgiu depois de `Ctrl+Shift+R`.

### ⚠️ Duas coisas que só apareceram em produção

**`FORCE_SSL=true`.** O Rails de produção recusa HTTP e redireciona para HTTPS, então a ponte
falhava em toda entrega com `SSL routines: wrong version number`. `CHATWOOT_URL` lá é
`https://chat.mobillirentals.com.br`, não `http://rails:3000` como no local. Isso não aparece em
desenvolvimento, onde não há FORCE_SSL.

**O PR #121 subiu sem o `channel/whatsapp.rb`.** Esse arquivo vem sempre modificado pelo `annotate`
e eu o filtrei do `git add` junto com outros oito que eram só comentário — mas ele tinha as três
linhas que ligam o provider (`PROVIDERS`, o roteamento e o `baileys?`). Resultado: a feature inteira
ficou inalcançável em produção, e o `MarkAsReadJob` matou 65 jobs em 6 minutos chamando um método
que não existia. Corrigido no #122. 💡 Antes de filtrar arquivo "sempre sujo":
`git diff <arquivo> | grep '^+' | grep -v '^+#'` mostra em um segundo se há conteúdo real no ruído.

## A decisão que define o resto

A caixa é **WhatsApp de verdade**, não `Channel::Api`. BotFlow, CSAT, verificador de número,
relatórios por canal e o fix de conversas duplicadas do #117 valem nela sem adaptação — apareceu
sozinho no primeiro teste, quando a política de atribuição distribuiu a conversa nova.

Deu certo porque o `Whatsapp::Providers::BaseService` **documenta como criar um provider**: é ponto
de extensão do upstream, não patch. O custo no Chatwoot é pequeno — `PROVIDERS` ganha `baileys`,
duas classes novas e o roteamento.

## O que atravessa

| | cliente → painel | painel → cliente |
|---|---|---|
| texto | ✅ | ✅ |
| resposta citada | ✅ | ✅ |
| mídia (imagem, áudio, documento) | ✅ | ✅ |
| recibo de entrega e leitura | ✅ | — |
| visto-azul | — | ✅ |
| "digitando…" | — | ✅ |
| acionar cliente **sem modelo aprovado** | — | ✅ |

Visto-azul e "digitando" **a API oficial não permite** — a Meta não expõe nenhum dos dois.

Áudio vai como **mensagem de voz** (`ptt: true`) e sem legenda: o WhatsApp não tem legenda em áudio.
Documento exige nome de arquivo, senão chega sem identificação no aparelho do cliente.

## LID: o obstáculo central

O WhatsApp está trocando o identificador do contato por **LID** (`<id>@lid`), que **não contém o
telefone**. A primeira mensagem de teste foi descartada por causa disso — o filtro exigia
`@s.whatsapp.net`.

Nas mensagens do cliente o número vem ao lado (`senderPn`). Nas que **saem** daqui, e nos recibos
delas, a chave só tem o LID — e o Baileys 6.7 **não traduz**. A ponte aprende pelos dois caminhos e
guarda em `identidades.json`.

⚠️ **Três armadilhas, todas descobertas em teste real:**

1. **Guardar só em memória não serve.** O primeiro eco testado depois de um rebuild foi descartado
   por LID desconhecido. Deploy reinicia.
2. **`limparPasta` apagava o `identidades.json`** — então "Reconectar" jogava fora tudo que a ponte
   sabia, e ecos e recibos paravam de resolver até cada cliente escrever de novo. O arquivo não é
   credencial e sobrevive ao repareamento do mesmo número.
3. **Filtrar por lista do que serve cega para o que é novo.** O filtro passou a barrar o que não
   serve (grupo, transmissão, status).

## Multi-sessão e o id da sessão

A ponte nasceu de um número só e virou multi-sessão antes de ir: uma pasta de credenciais por
número, endpoints por sessão, sessões retomadas do disco no boot. Duas conexões sobre a **mesma**
credencial se derrubam em loop — não dá para contornar com um container por número.

💡 **O id da sessão NÃO é o número.** A primeira versão usava o número como id, e a tela pedia que o
usuário o digitasse antes de parear — pedindo uma informação que a própria sessão traz. Hoje a
sessão tem id próprio (`s-<uuid>`), o número sai de `sock.user.id` ao conectar, e o `provider_config`
guarda `session_id`. Caixas criadas antes disso não têm `session_id` e continuam valendo pelo número.

## Trava de número ao reparear

A tela de configurações da caixa mostra o estado da conexão e permite reparear. **Só o número da
caixa é aceito**: parear outro faria a caixa seguir com o histórico e os contatos do antigo, mas
enviando de outro lugar — o cliente receberia resposta de um número que nunca contatou.

A trava fica **na ponte, no instante da conexão**: o pareamento acontece no WhatsApp, fora do nosso
alcance, então só dá para desfazer antes que qualquer mensagem trafegue. Validado em condição real.

## Configuração

Três configurações da instalação, porque na hora de parear ainda não existe caixa de onde lê-las:
`BAILEYS_BRIDGE_URL`, `BAILEYS_BRIDGE_TOKEN`, `BAILEYS_BRIDGE_WEBHOOK_TOKEN`. Sem elas a tela avisa
e nada mais muda de comportamento — **o deploy é seguro mesmo sem a ponte no ar**.

⚠️ A rota de webhook é pública e, fora da API oficial, **não há assinatura da Meta para conferir** —
sem o `webhook_verify_token` qualquer um injetaria mensagem na caixa.

## Separado do whatsapp-number-checker, de propósito

| | porta | papel |
|---|---|---|
| `whatsapp-number-checker` | 3300 | pergunta se um número tem WhatsApp |
| `whatsapp-baileys` | 3400 | recebe e envia mensagem de atendimento |

Sessões e números diferentes. Uma falha aqui não pode levar embora a verificação, que já roda em
produção.

🔴 **Nunca parear na ponte de teste um número que já tenha sessão Baileys em produção.** Em
05/10/2026 o número do verificador (um celular pessoal) foi pareado aqui para testar a tela de conexão.
O `logout` do teste de "Reconectar" fez o WhatsApp invalidar o device do verificador
(`conflict: device_removed`), e ele **saiu do ar em produção** — a verificação parou nos três
pontos em que é consultada. O serviço não se recupera sozinho (ao detectar `loggedOut` ele para e
pede intervenção), e foi preciso limpar as credenciais na VM e escanear o QR de novo.

💡 O cuidado **não é só "números diferentes entre si"** — eu tinha documentado isso e achei que
bastava. É **o mesmo número em dois serviços**: parecia seguro porque o verificador continuou
conectado logo após o pareamento, mas o `logout` seguinte derrubou. Para testar, usar número sem
outra sessão viva.

💡 Restaurar: `POST /logout` no checker (exige `X-Checker-Token`, que está no `.env` dele na VM),
que limpa as credenciais e gera QR novo, e então escanear por Configurações → Integrações.

## Pendências

- **Vídeo** não foi testado (imagem, áudio e documento foram).
- A tela de conexão não tem botão para **descartar** uma sessão que nunca pareou; a ponte já tem
  `DELETE /sessions/:id`.
- A ponte de produção **não é recriada pelo deploy do Chatwoot** — o CI só builda a imagem da
  aplicação. Mudança no código dela exige copiar e `docker compose up -d --build` na VM à mão.
- Dead set com ~5.477 jobs de ruído acumulado (5.365 do bug do Captain, 65 do erro do #121), nada
  reprocessável — esvaziar quando houver ocasião.

## Armadilhas do ambiente que custaram tempo aqui

💡 **Bind-mount do Docker no Windows não propaga eventos de arquivo**, então **rails e sidekiq ficam
com o código antigo em memória**. Isso me fez caçar um bug inexistente na citação: o `rails runner`
carregava o código novo e o Sidekiq rodava o antigo, e a citação chegava ora sim ora não. **Depois
de editar Ruby, reiniciar o container antes de testar pela UI.**

💡 O **sidekiq do compose de desenvolvimento nunca subia** (`Could not find rails-7.2.3.1`): faltava
o `entrypoint`, que é quem roda o `bundle install` das gems de dev. A fila ficava parada em silêncio
— o webhook respondia 200, o job era enfileirado e nada acontecia. Corrigido no `docker-compose.yaml`.

💡 **Prettier quebra handler Vue com identificador acentuado**: `@submit.prevent="começarPareamento"`
virava `"começarPareamento;"`, e com o `;` o Vue avalia a função sem chamá-la — o botão não fazia
nada. Identificadores em ASCII.

💡 **O WhatsApp às vezes só desenha a citação depois de sair e voltar na conversa.** A mensagem já
chegava certa; quase fui atrás de bug que não existia.
