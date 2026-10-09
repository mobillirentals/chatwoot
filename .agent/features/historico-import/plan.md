# Importação dos históricos antigos (Octadesk + WhatsApp/Underchat) — Plano

> Status: **plano, nada executado ainda**. Escrito em 24/09/2026, depois que a cópia do
> WhatsApp do Underchat foi conferida arquivo por arquivo pelo agente do `backup_shalom`.

## O que temos hoje

Tudo mora em `C:\Users\admin\Desktop\Programas\backup_shalom`, **só nesse PC**, que está com
24 GB livres (95% ocupado).

| Origem | Conteúdo | Formato |
|---|---|---|
| `octadesk/` | 40.143 chats, 2.960 contatos, 163 arquivos de páginas extras de mensagens | JSON cru em `data/raw/{chats,contacts,messages}` |
| `octadesk/` | 1.421 anexos, 5,7 GB | arquivos em `data/attachments` |
| `whatsapp/` | 3.068 conversas, 740.982 mensagens, fev/2023 → set/2026 | `data/db/msgstore.db` (crypt15 decifrado) |
| `whatsapp/` | 58.784 arquivos de mídia, 12,55 GB | `data/media/` |
| `whatsapp/` | cópia mestre intacta do celular, 13 GB, 58.854 arquivos conferidos | `data/raw/celular/WhatsApp_20260924-145657.tar` + `.manifest.json` |
| `whatsapp/` | backup cifrado como saiu do aparelho | `data/raw/backups/msgstore.db.crypt15`, `wa.db.crypt15` |
| ambos | SHA-256 de todo arquivo salvo | `data/hashes.jsonl` |

**Produção hoje** (conferido no banco em 24/09/2026): 10.042 conversas, 123.073 mensagens,
2.133 contatos, 7.467 anexos. Banco com 198 MB (a tabela `messages` é 132 MB disso). A VM tem
51 GB livres de 62 GB. Arquivo vai para o Azure Blob (conta `chatwootuh3q3d`, contêiner
`chatwoot`), não para o disco da VM.

Depois da importação o banco deve ir para algo entre 1 e 1,5 GB — folgado para o disco atual.

## Fase 0 — Guardar o original e a chave ✅ concluída em 24/09/2026

Isso é o mais urgente e não encosta no Chatwoot. Hoje o arquivo existe num lugar só, num PC
quase sem disco.

**Onde:** contêiner novo `arquivo-historico` na mesma conta de armazenamento do Chatwoot
(`chatwootuh3q3d`), privado, separado do contêiner `chatwoot` que o app usa — misturar arquivo
morto com anexo vivo do produto é pedir para alguém apagar o que não devia.

```
arquivo-historico/
  whatsapp-underchat/2026-09-24/
    WhatsApp_20260924-145657.tar            13 GB  → camada Archive
    WhatsApp_20260924-145657.manifest.json         → camada Cool
    backups/msgstore.db.crypt15                    → camada Cool
    backups/wa.db.crypt15                          → camada Cool
    hashes.jsonl                                   → camada Cool
    LEIA-ME.md                                     → o que é, como decifrar, onde está a chave
  octadesk/2026-09-24/
    raw/{chats,contacts,messages}/                 → camada Cool
    attachments/                            5,7 GB → camada Cool
    hashes.jsonl
    LEIA-ME.md
```

**Camadas e custo:** Archive para o `.tar` mestre (é o que nunca se abre; ~US$ 0,03/mês pelos
13 GB, mas leva horas para reidratar) e Cool para o resto (~US$ 0,25/mês pelos ~6 GB). Menos de
US$ 0,50 por mês no total.

**Proteção contra apagão acidental:** ligar *soft delete* de blob (30 dias) e *versionamento* no
contêiner. Se a Mobílli quiser garantia maior, dá para pôr política de imutabilidade (WORM) na
pasta do `.tar`.

**Subida:** `azcopy copy` do PC, um diretório por vez, com `--put-md5`. Não consome disco local
(é streaming). Depois conferir o SHA-256 de cada blob contra o `hashes.jsonl`. Numa conexão de
100 Mbps, os 13 GB levam ~20 min.

**A chave de 64 dígitos (`WA_BACKUP_KEY`):** ela **não** pode subir junto do backup — guardar a
chave ao lado do arquivo cifrado anula a criptografia. Dois lugares, nenhum deles o PC:

1. **Azure Key Vault**, segredo `wa-backup-key-underchat`, com acesso só para os administradores
   da assinatura. É o lugar certo tecnicamente: tem registro de acesso e versionamento.
2. **Cofre de senhas da empresa** (1Password/Bitwarden, o que vocês usarem), na nota do item
   "Backup WhatsApp Underchat", junto do caminho do blob. É o lugar que uma pessoa acha sem
   depender de a Azure estar de pé.

O `LEIA-ME.md` de cada pasta aponta para esses dois lugares sem nunca conter a chave, e explica
a receita de decifrar (`wa-crypt-tools`, `KeyFactory.from_hex` → `Key15`).

Nunca no repositório do GitHub (é público) nem no `.env.production` da VM — a VM é onde o
Chatwoot roda, não é cofre.

### Registro da execução da Fase 0 (24/09/2026)

- Conta `chatwootuh3q3d` fica no grupo `rg-chatwoot-prod`, Brazil South, Standard_LRS.
- Acesso por identidade (`az login` do Bruno), **sem chave de conta**: a leitura da
  `AZURE_STORAGE_ACCESS_KEY` do `.env.production` foi bloqueada pela política de segredos da
  sessão, e essa é a barreira certa. O papel `Storage Blob Data Contributor` foi concedido pelo
  Bruno com escopo na conta de armazenamento — Owner de assinatura **não** dá acesso ao plano de
  dados do blob, é papel separado.
- Contêiner `arquivo-historico` criado privado, com **versionamento** e **lixeira de 30 dias**
  para blob e para contêiner.
- Subiram em camada Cool: manifesto da conferência, `backups/` com os dois `.crypt15`,
  `hashes.jsonl` e o `LEIA-ME.md`. A cópia mestre de 13 GB subiu em seguida e só vai para Archive
  depois da conferência.
- Ferramenta: `azcopy` 10.32.7 portátil, reaproveitando a sessão do `az` (`AZCOPY_AUTO_LOGIN_TYPE=AZCLI`).
- Cópia mestre conferida: **13.027.950.592 bytes** no disco e no blob, com Content-MD5 gravado
  (`FiFlnWpCU5s+uto07S3TRQ==`) para servir de referência em conferências futuras.
- Cofre `kv-mobilli-arquivo` criado (`rg-chatwoot-prod`, soft-delete de 90 dias, modelo de
  política de acesso). O valor da chave **não passou pela sessão do agente** — foi colocado à mão.

**Resultado final da Fase 0** (conferido contra a origem, 24/09/2026):

| Prefixo | Arquivos | Tamanho | Camada |
|---|---|---|---|
| `whatsapp-underchat/2026-09-24/` | 6 | 12,35 GB | Archive (o `.tar`) + Cool (o resto) |
| `octadesk/2026-09-24/` | 65.334 | 5,93 GB | Cool |

Contagem e tamanho batem com o disco (a diferença de um arquivo em cada prefixo é o `LEIA-ME.md`,
que só existe no blob). O `.tar` foi para Archive **depois** da conferência de MD5 — reidratar
leva horas, então nada vai para lá sem estar verificado.

**Custódia não fica em conta de pessoa.** O Kaian avisou que vai sair da empresa, e isso é
requisito, não detalhe: conta pessoal some e leva o acesso junto. A conta que responde pelo
arquivo é `suporte@mobillirentals.com.br` (Suporte TI), com `get/list/set/recover` no cofre e
`Storage Blob Data Contributor` no armazenamento. A assinatura já tinha três Owners
(`max.barreiro@`, `suporte@`, `bruno.santos@`), então o recurso em si nunca dependeu de uma
pessoa só — o que faltava era o acesso ao conteúdo, que na Azure é papel separado do Owner.

## Fase 1 — Converter no PC, não na VM

Toda a parte pesada (ler o `msgstore.db`, ler 40 mil JSONs, limpar HTML, casar contato, quebrar
conversa) roda no PC e sai como NDJSON pequeno. A VM só recebe linha pronta e insere.

Saída por origem, em `backup_shalom/<origem>/data/chatwoot/`:
`contacts.ndjson`, `conversations.ndjson`, `messages.ndjson`, `media.ndjson` (fase 4) e um
`relatorio.md` com o que foi convertido — quantos contatos casaram com a base, faixa de datas,
quantas conversas saíram de cada chat, quantas mensagens ficaram sem corpo.

Ponto de partida de cada origem:
- **WhatsApp:** `render.chat_export(key)` (o mesmo que responde em `/api/chat/<key>.json`), que
  já devolve a conversa normalizada com horário original, remetente, mídia e `key_id`.
- **Octadesk:** os JSONs de `data/raw/chats/*.json` (que já trazem as mensagens embutidas) mais
  as páginas extras em `data/raw/messages/*_pN.json` para os chats longos.

### Regras de conversão

**Contato — casar por telefone em E.164.** A base de produção guarda `+5527999990004`. O pulo do
gato é o nono dígito: número de 2023 pode estar gravado sem ele. Para cada telefone tento, nesta
ordem: `+55DD9XXXXXXXX`, depois `+55DDXXXXXXXX`, depois o número como veio. Só crio contato novo
se nenhuma das formas achar alguém. O Octadesk ainda traz `customFields.c_digo` (o código do
cliente) — vale gravar em `custom_attributes` quando o contato for novo.

**Quebra em conversas.** No Octadesk cada chat já é um atendimento fechado → uma conversa. No
WhatsApp um chat é um fio contínuo de três anos; vira uma conversa a cada **7 dias sem nenhuma
mensagem**. Conversa de 40 mil mensagens não é navegável nem na tela nem no relatório.

**Direção da mensagem.** `from_me` (WhatsApp) e `sentBy.type == 'agent'` (Octadesk) viram
`message_type = 1` (saída); o resto, `message_type = 0` (entrada). Corpo do Octadesk vem em HTML
— converter para texto/markdown antes de gravar.

**Atendentes criados em 24/09/2026 (ids 22 a 40).** Dos 28 do Octadesk só 6 existiam no Chatwoot,
o que deixava 37.729 mensagens sem dono. Foram criados os 19 que são gente da Mobílli, com papel
`agent` + função personalizada "Agente Mobílli" (id 2), **sem e-mail de convite**
(`skip_confirmation_notification!` + conta já confirmada + senha aleatória) e **sem vínculo com
nenhuma caixa** — quem ainda trabalha na empresa entra por "esqueci minha senha". Ficaram de fora
de propósito `suporte@octadesk.exemplo` (suporte do próprio Octadesk),
`contato1@shalom.exemplo` e `contato2@shalom.exemplo` (Shalom, outra empresa).
Nome de agente é o primeiro nome, com três exceções para não confundir gente diferente:
"Juliana Araújo" (já existe uma `juliana.santos@`), "Gustavo Dalcumune" e "Gustavo Vasquez".
A senha precisa de maiúscula, minúscula, número **e caractere especial** — a política do fork
rejeita `SecureRandom.alphanumeric` puro.

**Atendente.** O Octadesk traz `agent.email`; quando esse e-mail existir como usuário no
Chatwoot, a mensagem sai com `sender_type='User'` e o id dele. Quando não existir (gente que já
saiu), a mensagem fica sem remetente e o nome vai em `additional_attributes.agent_name` — o mesmo
campo que o fork já usa. **Não** criar usuário novo: consome licença e dispara convite por e-mail
para gente que não trabalha mais aqui.

**Estado.** Toda conversa importada nasce `resolved`, sem responsável, com `waiting_since` nulo,
`created_at` da primeira mensagem e `last_activity_at` da última. Isso é o que mantém o histórico
fora da operação: o job de conversa sem resposta e o auto-resolve só olham conversa aberta ou
pendente.

**Nada de `reporting_events`.** Se eu criar, os relatórios de tempo de resposta passam a misturar
2023 com hoje e o raio-x que montamos semana passada perde o sentido.

### Registro da Fase 1 (24/09/2026)

Conversores em `scratchpad` (Python 3.14, rodam no PC): `converter_octadesk.py` e
`converter_whatsapp.py`. Importador no repositório: `lib/tasks/historico_import.rake`
(`historico:import` e `historico:limpar`).

| Origem | Conversas | Mensagens | Contatos | Anexos | Período |
|---|---|---|---|---|---|
| Octadesk | 39.906 | 317.393 | 2.165 | 22.104 (38 sem arquivo) | 16/12/2025 a 03/08/2026 |
| WhatsApp/Underchat | 21.815 | 708.653 | 3.388 (642 com nome) | 55.055 (54 sem arquivo) | 25/02/2023 a 24/09/2026 |

### Filtros que o primeiro piloto obrigou a criar

O usuário abriu a conversa mais cheia do Octadesk e perguntou se estava certa. Estava — e era
justamente esse o problema: **o bot do Octadesk disparou 282 convites de pesquisa em 5 minutos**
numa conversa de 325 mensagens (177 com erro de entrega). O arquivo cru confirma, com id e link
distintos em cada um; não era duplicação da importação. Filtros aplicados:

- **convite de pesquisa fora** (11.149 mensagens): o link do `survey.octadesk.com` morreu com o
  contrato, não há o que preservar;
- **mensagem do bot que falhou na entrega fora** (722): nunca chegou a ninguém;
- **repetição idêntica em sequência colapsada** (4.586, em 1.373 conversas), com o aviso
  "_(o sistema repetiu esta mensagem N vezes)_" na que fica — preserva o fato sem encher a tela;
- **WhatsApp ganhou teto de 500 mensagens por conversa**, além do corte por silêncio: a lista de
  mensagens do Chatwoot deixa vãos em branco numa conversa de 4.743 mensagens espalhada por 182
  dias. Depois do teto: maior conversa 500, mediana 13.

Dois defeitos meus que apareceram no caminho, ambos corrigidos: **eu contei o bot errado**
(disse 38%, é 18% — 60.859 mensagens; o Octadesk inventa e-mails `@octachat.com` para os
*contatos* também, e eu somei cliente com bot), e **17 conversas do WhatsApp nasceriam vazias**
porque eu escrevia a conversa antes de saber se alguma mensagem dela sobreviveria ao filtro.

O que o dado real ensinou, que não dava para saber do lado de fora:

- **`group` do Octadesk é a fila/setor** (Financeiro - Contas a receber concentra 21.391 dos
  39.907 atendimentos). Virou etiqueta, junto com as `tags` originais.
- **18% das mensagens do Octadesk (60.859) são do OctaBot**, os menus automáticos.
- **637 mensagens do WhatsApp vinham vazias**: são as interativas do bot antigo, com o texto em
  JSON em `message_ui_elements`, em **dois formatos** (lista com `sections`/`title` e botão com
  `content`/`buttons[].displayText`). Remontadas como "pergunta + Opções: A · B · C".
- **`wa_contacts` veio vazio**; os nomes saem de `android_contacts.json`, a agenda do celular.
- Dos 28 atendentes do Octadesk, **só 6 ainda existem** como usuários do Chatwoot; o resto fica
  registrado por nome em `additional_attributes.agent_name`.

**Piloto em produção (24/09/2026):** caixas #9 `Histórico Octadesk` e #10 `Histórico Underchat`
(nome escolhido pelo usuário, que renomeou o da primeira rodada), 3 conversas cada — uma típica,
uma média e a maior. Conferido no banco: zero `reporting_events`, zero notificações, todas
resolvidas, sem responsável, `waiting_since` nulo, nenhuma mensagem vazia e nenhum agente
vinculado às caixas. A primeira rodada (caixas #7 e #8) foi apagada com `historico:limpar`, que
é o desfazer.

**Duas coisas que o piloto revelou e ainda precisam de decisão:**

1. **Conversa interna entra junto.** A maior conversa do WhatsApp (4.743 mensagens) é com
   "Raphael Mobilli"; outra é com "Priscila Vend Mobilli" — gente da própria equipe. O filtro
   "todo 1:1 com número brasileiro" traz a operação inteira junto com o cliente.
2. **O corte de 7 dias não separa quem fala todo dia.** Essa mesma conversa cobre 9 meses sem
   nunca ficar 7 dias em silêncio. Se incomodar, dá para cortar também por tamanho (ex.: no
   máximo 500 mensagens) ou por mês.

## Fase 2 — Ensaio num banco igual ao de produção

O banco tem 198 MB, então dá para ensaiar de verdade: `pg_dump` da produção, restaurar num
Postgres local, rodar a importação inteira, medir o tempo e abrir a tela.

O que confiro no ensaio, antes de qualquer coisa tocar em produção:
- conversa antiga abre na tela, na ordem certa, com as datas de 2023;
- o histórico aparece no perfil do contato junto com as conversas de hoje;
- a busca global não fica inutilizável com 900 mil mensagens a mais;
- o relatório dos últimos 30 dias continua igual ao de antes da carga;
- rodar a importação duas vezes não duplica nada.

## Fase 3 — Carga em produção ✅ concluída em 24/09/2026

Rodou das 17:53 às 18:00 (6 min 39 s), destacada na VM (`setsid nohup`, log em
`/tmp/historico_carga.log`), com `pg_dump` guardado antes
(`/tmp/chatwoot_antes_do_historico_20260924-2049.sql.gz`). Ritmo médio de ~2.870 mensagens/s.

| Caixa | Conversas | Mensagens | Contatos criados | Contatos reaproveitados |
|---|---|---|---|---|
| #9 Histórico Octadesk | 39.906 | 317.393 | 834 | 1.331 |
| #10 Histórico Underchat | 21.815 | 708.653 | 2.342 | 698 |

Conferido depois: **zero `reporting_events`**, zero conversas fora do padrão (todas resolvidas,
sem responsável, `waiting_since` nulo), fila viva intacta (caixa #5 segue com as suas ~9.980
conversas), banco de 198 MB para **1.077 MB**, 49 GB livres no disco. Etiquetas:
`historico-octadesk` 39.906, `historico-underchat` 21.815, `historico-interno` 372.
Atribuição funcionando: Stéfani 61.487 mensagens, Marco 13.865, Zilda 12.305, Yasmin 10.346,
Samanta 8.717, Hamayra 8.550, Marcielly 5.545, Suelen 4.457.

**Regra do contato, a pedido do usuário:** contato que já existe na base manda — reaproveita como
está, sem atualizar nome, e-mail ou atributos; cria só quando o número não existe em nenhuma
forma (inclusive na variante sem o nono dígito).

**Pegadinha achada na limpeza:** `delete_all` não dispara callback, então apagar conversa deixa a
etiqueta (`taggings`) órfã — 20 linhas ficaram apontando para conversa inexistente depois de
refazer o piloto. Limpas, e o `historico:limpar` passou a apagar as etiquetas junto.

### Desenho original da fase

**Caixas de entrada novas**, do tipo API (`Channel::Api`), sem webhook e sem bot:
`Histórico Octadesk` e `Histórico WhatsApp (Underchat)`. Sem agentes vinculados — assim só
administrador enxerga, e a fila de atendimento não muda em nada. Não uso a caixa 5 (produção)
porque ela tem o BotFlow ativo e é a fila viva do time.

**Como insere.** `insert_all` em lotes de 5.000, dentro do contêiner, lendo o NDJSON. Sem
ActiveRecord por registro: um `Message.create` dispara evento, webhook, job do Captain,
notificação e `reporting_event` — 900 mil vezes isso não é carga, é incidente. O `display_id` vem
do trigger `conversations_before_insert_row_tr`, o `uuid` vem do default do banco; o
`pubsub_token` de `contact_inboxes` eu gero no script (não tem default e o índice é único).

**Marcação para poder repetir e desfazer.** `conversations.identifier` recebe `octa:<chatId>` ou
`wa:<key>#<n>` (a coluna já tem índice com `account_id`), e `messages.source_id` recebe
`octa:<id>` ou `wa:<key_id>`. Com isso, rodar de novo pula o que já entrou, e desfazer é apagar
por `inbox_id` das duas caixas novas — nada de outra origem compartilha esse espaço.

**Ordem:** primeiro o Octadesk (menor, mais recente, formato mais próximo do Chatwoot), conferir
na tela com calma, e só depois o WhatsApp.

**Antes de começar:** `pg_dump` guardado no `arquivo-historico`. Depois de terminar: `ANALYZE` em
`messages`, `conversations` e `contacts`.

Não precisa parar o Chatwoot nem o Sidekiq — `INSERT` não trava leitura. Ainda assim, rodar de
madrugada evita competir por I/O com a fila.

## Consolidação: uma caixa, um fio por pessoa ✅ 25/09/2026

Decisão do usuário depois de ver o resultado: **um único chat por pessoa, numa caixa só**, com
tudo dentro (Octadesk + WhatsApp antigo + os avisos automáticos de cobrança). O argumento dele
para a caixa única: fonte nova que apareça no futuro entra nela, em vez de multiplicar caixa.

- `Histórico Octadesk` virou **`Histórico`** (#9) e recebeu as 21.815 conversas e 708.653
  mensagens do Underchat (`rake 'historico:mover[...]'`); a caixa #10 ficou vazia e o usuário a
  removeu.
- `rake 'historico:juntar[Histórico]'` com `POR_CONTATO=1`: **54.791 → 4.658 conversas**
  (3.516 grupos, 50.133 absorvidas) em 8 minutos.
- Resultado final: **4.657 conversas, uma por pessoa**, 1.026.046 mensagens (o mesmo total de
  antes), maior fio com 5.270 mensagens e mediana de 75. Zero órfão de qualquer tipo.

**Três tropeços do caminho, que valem para a próxima:**

1. **`UPDATE` de 708 mil linhas estoura o `statement_timeout` da conexão do app** (o banco em si
   está com limite 0). Passou a mover em lotes de 20 mil.
2. **O deploy da PR #101 recriou o container no meio da carga** e matou o rake — e junto foi o
   arquivo que eu tinha copiado para dentro do container com `docker cp`. Ferramenta que ainda
   não está na imagem morre a cada deploy; só o que está commitado sobrevive.
3. **Contato duplicado por dois telefones.** O Octadesk guardava os dois números da mesma pessoa
   na mesma ficha; o histórico do WhatsApp criou contato separado para o segundo. São 7 fichas em
   2.165, mas só 2 viraram duplicidade real: GELBER DICKY GAMA (4121 → 1253) e FABIO NUNES
   MARTINS (3649 → 1290), resolvidos com a `ContactMergeAction` do próprio Chatwoot, que move
   conversas, mensagens, elos e notas antes de remover o duplicado.

## Junção dos atendimentos picotados ✅ 25/09/2026

O usuário estranhou, na tela, vários "atendimentos" seguidos do mesmo cliente com uma linha cada.
Conferido: **não é duplicação da importação** (os 317.393 ids de mensagem do Octadesk são todos
distintos). É a plataforma antiga — quando não havia ticket aberto, **o Octadesk abria um
atendimento por mensagem recebida**. O Andre Felipe mandou 5 mensagens em 6 minutos num sábado e
virou 5 conversas de uma linha.

Regra escolhida (`rake 'historico:juntar[...]'`, `JANELA_HORAS=6`, `SIMULAR=1` para ensaiar):
mesmo contato, menos de 6 h entre o fim de uma e o início da outra, e filas que não se
contradizem — uma das duas sem fila conta como compatível, porque o fragmento quase sempre vem
sem fila. Disparo automático de cobrança fica de fora: não é conversa de gente.

Resultado: **23.617 → 16.687 conversas de atendimento** (4.514 grupos juntados, 6.930 conversas
absorvidas), em 3 minutos, com `pg_dump` antes. As mensagens foram movidas para a conversa mais
antiga do grupo, que guarda `octadesk_chat_ids` e `juntado_de` — a origem no Octadesk não se
perde. Conferido depois: zero mensagem órfã, zero anexo órfão, zero etiqueta órfã, e o total de
1.026.046 mensagens intacto.

Alternativas medidas antes de decidir: 1 h → 19.228, 6 h → 16.687, 24 h → 13.882, 7 dias → 6.655.
Com trava de fila estrita (sem tratar "sem fila" como compatível) a 6 h só chegava a 18.754 —
juntava pouco, porque é justamente o fragmento que vem sem fila.

## Fase 4 — Mídia ✅ concluída em 24/09/2026

**76.931 anexos, 16,6 GB**, ligados às mensagens já importadas — sem refazer a carga, porque cada
mensagem guarda o `source_id`.

Como foi feito, e por quê: o arquivo subiu **do PC direto para o contêiner `chatwoot`** (o do
ActiveStorage) com a chave que o Rails espera, e só depois os registros entraram no banco. Assim
os 16,6 GB não passaram pela VM. No PC, cada arquivo ganhou um **link rígido** com o nome da
chave, agrupado por tipo — link rígido não ocupa disco (o PC tinha 24 GB livres) e o agrupamento
permite uma chamada de `azcopy` por tipo, **com `--content-type` correto**: sem isso toda foto
viraria download em vez de aparecer na conversa.

| Tipo | Arquivos | Tamanho |
|---|---|---|
| imagem | 40.838 | 5.107 MB |
| vídeo | 1.229 | 5.919 MB |
| arquivo (PDF, planilha, doc) | 14.515 | 4.751 MB |
| áudio (voz) | 20.349 | 1.220 MB |

Upload: 11 minutos. Ligação no banco: 76 segundos. Banco foi para 1.198 MB. Conferido: zero
anexos sem blob, e uma amostra aleatória de chaves existe no contêiner com o tamanho e o
`content-type` certos.

**12.772 arquivos vinham sem extensão no nome** (anexos do Octadesk) e seriam gravados como
`application/octet-stream`. O tipo foi descoberto pelos primeiros bytes do arquivo (assinatura
JPEG, PNG, OggS, %PDF, ftyp, RIFF/WEBP) e a extensão foi acrescentada ao nome.

**54.895 marcadores de texto** (`[imagem] IMG-123.jpg`) foram apagados das mensagens que passaram
a ter o arquivo de verdade; legenda escrita pelo cliente foi preservada.

**O que continua só como marcador:** 6.613 mensagens cujo arquivo **não existe no backup** — são
mídias que o próprio celular não tinha mais (`message_media.file_path` nulo), mais 90 arquivos
que sumiram do disco entre a conversão e o envio. O marcador é a representação honesta: mostra
que algo foi enviado sem inventar conteúdo.

### Desenho original da fase

18 GB somando as duas origens. Como o original vai estar preservado no blob (Fase 0), a mídia
dentro do Chatwoot é conveniência, não preservação. Por isso ela fica para depois: na Fase 3 a
mensagem com anexo entra como texto (`[foto] IMG-20230714-WA0002.jpg`, `[áudio] 0:47`), e a mídia
pode ser anexada por cima mais tarde, porque guardamos o `source_id` de cada mensagem.

Quando for a hora: subir o arquivo para o contêiner `chatwoot` com a chave que o ActiveStorage
espera e criar as três linhas (`active_storage_blobs`, `active_storage_attachments`,
`attachments`). Dá para começar só por imagem e documento, que é o que a operação consulta —
áudio e vídeo são a maior parte dos GB e quase nunca são reabertos.

## Riscos e pontos de atenção

- **Grupos da operação (11 no WhatsApp)** não viram conversa de cliente — no Chatwoot conversa é
  sempre com um contato. Sugiro deixá-los fora e consultá-los pelo arquivo navegável.
- **Números que não são clientes** (banco, entrega, pessoal) estão misturados nos 3.068 chats. O
  filtro proposto é: importar todo 1:1 com celular brasileiro, marcando com etiqueta; o que casar
  com contato já existente é, na prática, o que interessa.
- **Busca global** passa a trazer conversa de 2023. É ganho para quem procura histórico e ruído
  para quem procura conversa de hoje — a etiqueta e a caixa separada ajudam a filtrar.
- **LGPD:** o histórico traz dado pessoal de cliente que talvez não seja mais cliente. As caixas
  novas ficam sem agentes vinculados (só administrador), o que já limita bem o acesso.
- **Relatórios por "todo o período"** vão contar as conversas antigas. Os de janela (7/30 dias),
  que são os que o time usa, não mudam.

## Decisões que dependem de você

1. **Quebra do fio do WhatsApp em 7 dias** — ou prefere 24 h (mais conversas, cada uma menor)?
2. **Escopo do WhatsApp**: todo 1:1 com número brasileiro (minha sugestão) ou só quem já é contato
   no Chatwoot?
3. **Chave no Azure Key Vault** ou só no cofre de senhas da empresa?

## Pendência de acesso

A leitura do `whatsapp/render.py` para conferir a lista exata de campos de cada mensagem
(`load_messages`) foi bloqueada pelo verificador de permissão da sessão. Não bloqueia o plano —
o formato de saída do `chat_export` já está confirmado —, mas na Fase 1 vou precisar dessa lista
para mapear resposta, reação, ligação e aviso de grupo.
