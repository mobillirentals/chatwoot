# Análise técnica — Disparo em massa via planilha (WhatsApp)

> Status: análise de viabilidade, nada implementado ainda. **Revisada em 14/07/2026** depois de segunda opinião (outra IA) — ver `## Revisão` no fim pra ver o que mudou e por quê.
> Pedido original: personalizar "Campanhas do WhatsApp" para aceitar upload de planilha (telefone + variáveis nomeadas por linha), no estilo do "Disparo em Massa" do Octadesk, eliminando a etiquetagem manual de contatos.

## Achado principal (pesquisa prévia)

**O motor de personalização por variável já existe e já funciona — só está incompleto na ponta de entrada de dado.**

O Chatwoot (neste fork) já tem, rodando em produção hoje:

1. **Import de CSV joga qualquer coluna extra em `custom_attributes` do contato.**
   `DataImport::ContactManager#update_contact_attributes` ([app/services/data_import/contact_manager.rb:61-67](../app/services/data_import/contact_manager.rb#L61)):
   ```ruby
   contact.assign_attributes(custom_attributes: contact.custom_attributes.merge(
     params.except(:identifier, :email, :name, :phone_number)
   ))
   ```
   Ou seja: uma planilha com colunas `nome-contato, telefone, contrato, vencimento` já vira, hoje, um contato com `custom_attributes: {contrato: '12345', vencimento: '17/07/2026'}` — sem escrever uma linha de código.

2. **Campanha de WhatsApp já renderiza variável por contato via Liquid**, lendo exatamente esse `custom_attributes`.
   `Whatsapp::LiquidTemplateProcessorService` + `ContactDrop#custom_attribute` ([app/drops/contact_drop.rb:22-25](../app/drops/contact_drop.rb#L22)) — comprovado por teste automatizado (`spec/services/whatsapp/oneoff_campaign_service_spec.rb:156-197`, `{{ contact.custom_attribute.contrato }}` sendo substituído por contato).

3. **Template Meta (HSM) já é obrigatório e já funciona** — `Whatsapp::OneoffCampaignService` ([app/services/whatsapp/oneoff_campaign_service.rb](../app/services/whatsapp/oneoff_campaign_service.rb)) nem aceita campanha de WhatsApp sem `template_params` (linha 55-58) — ou seja, **já evita** o problema clássico de mensagem fora da janela de 24h.

**O que falta não é o motor — é a costura entre "subir planilha" e "criar campanha".** Hoje são duas telas separadas:

- **Contatos → Importar** ([ContactImportDialog.vue](../app/javascript/dashboard/components-next/Contacts/ContactsForm/ContactImportDialog.vue)) — sobe o CSV, cria/atualiza contatos com os `custom_attributes` da planilha, e se a planilha tiver uma coluna `labels`, já aplica a etiqueta.
- **Campanhas → Nova campanha de WhatsApp** ([WhatsAppCampaignForm.vue](../app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignForm.vue)) — escolhe a etiqueta como público (linha 154-157, **hardcoded `type: 'Label'`** — é a única forma de público que existe), escolhe o template aprovado, e escreve **uma expressão Liquid por variável do template** (`{{ contact.custom_attribute.vencimento }}`) que vale pra campanha inteira.

**Isso significa que o fluxo que você descreveu — telefone + variáveis por linha — já é possível hoje, na prática, fazendo:** upload em Contatos com uma coluna `labels` (ex.: `vencimento-11-07`) → criar campanha de WhatsApp com essa etiqueta como público → escrever a expressão Liquid de cada variável do template. Três telas, conhecimento de Liquid exigido do operador, mas **funciona sem nenhuma linha de código nova**.

Isso muda a pergunta de "dá pra fazer?" para "vale a pena construir uma tela única, e onde?" — é isso que os 6 pontos abaixo respondem.

---

## O que NÃO existe (gaps reais)

- **Nenhuma tela única** que junte upload + mapeamento + disparo. É sempre duas ações manuais.
- **Nenhum mapeamento automático** coluna → variável do template. O operador escreve a expressão Liquid à mão, por variável, uma vez por campanha.
- **Nenhum preview com dado real** de vários destinatários antes de disparar — o formulário de campanha mostra a prévia do template, não o resultado renderizado por linha da planilha.
- **Nenhum XLSX.** Só CSV, em todo o projeto (sem gem `roo`/`caxlsx`/`rubyXL`).
- **Nenhum rate limit / lote / retry para envio da Meta.** `Whatsapp::OneoffCampaignService#process_audience` ([linha 66-73](../app/services/whatsapp/oneoff_campaign_service.rb#L66)) roda um `.each` síncrono, **dentro de um único job Sidekiq**, sem lote, sem espera entre mensagens, sem tratar rate-limit (HTTP 429) da Graph API. Isso já é um risco hoje (etiquetagem manual tende a gerar públicos pequenos); um recurso de planilha tende a aumentar o tamanho típico do público, então esse ponto **precisa ser resolvido de qualquer forma**, incorporando ou não a planilha na campanha.
- **Nenhum relatório de envio.** Falha de API é só logada (`rescue StandardError`, [linha 104-108](../app/services/whatsapp/oneoff_campaign_service.rb#L104)) — o operador não descobre quantos falharam nem por quê, a não ser lendo o log do servidor.

---

## Resposta aos 6 pontos pedidos

### 1. Incorporar em "Campanhas do WhatsApp" ou módulo novo?

**Recomendo: não estender o model `Campaign` — construir um fluxo próprio, mas reaproveitando 100% do motor de template/envio do WhatsApp.**

Por quê: `Campaign` é modelado em torno de **público persistente por etiqueta** e **agendamento recorrente** (`campaign_type: ongoing/one_off`, `trigger_only_during_business_hours`, `trigger_rules`, o scheduler que varre campanhas `active` a cada ciclo). Um disparo de planilha é o oposto disso: uma rajada **única**, disparada uma vez, com um arquivo anexado que não faz sentido reaproveitar depois. Isso tem muito mais a cara do `DataImport` (model com `has_one_attached :file`, status `pending/processing/completed/failed`, relatório de falha) do que do `Campaign`.

Forçar isso dentro do jsonb `audience` (ex.: inventar `{type: 'Spreadsheet', ...}`) exigiria mexer em validações do `Campaign`, no front que já fixa `type: 'Label'`, e ainda deixaria um model de "campanha recorrente" carregando um conceito de "arquivo de uma vez só" que não combina com o resto do model.

**Para o usuário, a experiência pode continuar unificada**: um item novo dentro do menu "Campanhas do WhatsApp" (ex.: aba ou botão "Disparo por planilha"), só que por trás é um model/fluxo separado que **chama os mesmos serviços de template** (`Whatsapp::TemplateProcessorService`, `Whatsapp::PopulateTemplateParametersService` — esses já são genéricos, não amarrados ao `Campaign`).

### 2. Arquitetura recomendada

- **Novo model de "disparo"** (ex.: `WhatsappBulkDispatch`), espelhando o `DataImport` na forma (`has_one_attached :file`, `status` enum `pending/processing/completed/failed`, referência ao `inbox`/template escolhido), mas **sem depender de `Contact`**.
- **`has_many :recipients`** — uma tabela nova (`whatsapp_bulk_dispatch_recipients` ou nome parecido) com `phone_number`, `variables` (jsonb — os valores daquela linha específica: `contrato`, `vencimento`, etc.), `status` (`pending/sent/failed`), `error_message`. **Isso substitui a ideia de gravar em `Contact.custom_attributes`** — resolve dois problemas de uma vez: não cria contato permanente pra quem nunca respondeu, e não corre o risco de um disparo do mês seguinte sobrescrever o valor do anterior (`custom_attributes` é uma coluna só por contato; a tabela de destinatários é uma linha por disparo).
- **Envio sem exigir `Contact` prévio.** `channel.send_template(phone_number, template_info, nil)` já funciona hoje só com um número de telefone — é assim que a campanha atual envia (`Whatsapp::OneoffCampaignService#send_whatsapp_template_message`). Quando o cliente responder, o webhook de entrada (`Whatsapp::IncomingMessageIdentifierHelper#set_contact_from_message`) já faz `find_or_create_contact_inbox` sozinho — não precisamos criar nada na mão pra isso funcionar.
- **Liquid ganha um contexto novo, `row`**, ao lado de `contact`/`agent`/`inbox`/`account` em `Whatsapp::LiquidTemplateProcessorService` — os `drops` hoje são montados na hora do render (`'contact' => ContactDrop.new(contact), ...`); acrescentar `'row' => variables_hash` do destinatário é uma mudança pequena e aditiva, não mexe no que já existe. O operador escreve `{{ row.vencimento }}` em vez de `{{ contact.custom_attribute.vencimento }}`.
- **Processamento em lote, não num `.each` só.** Diferente do `Whatsapp::OneoffCampaignService` de hoje: enfileirar **um job por lote** (ex. 50-100 destinatários), não um job monolítico pra campanha inteira — assim uma planilha de 2 mil linhas não trava um único worker por minutos, e uma falha não derruba o processamento inteiro.
- **Rate limiting real**, hoje inexistente em todo o projeto. Mais simples: um contador no Redis (`Redis::Alfred`, já usado pelo Captain) limitando N envios/segundo por canal, respeitando o tier de mensageria do número no WhatsApp Cloud API. Não precisa de gem nova.

### 3. Fluxo de upload/validação/processamento

Espelhar o `DataImportJob` ([app/jobs/data_import_job.rb](../app/jobs/data_import_job.rb)) na forma geral: upload assíncrono via ActiveStorage (`attach` no controller, processa depois — evita travar a resposta HTTP), validação linha a linha, linhas válidas e rejeitadas em listas separadas.

**CSV e XLSX desde a primeira versão.** O operador normalmente recebe a planilha pronta do Excel — pedir pra salvar como CSV antes é uma etapa a mais que não precisa existir. A gem `roo` é madura e padrão do ecossistema Ruby pra isso; o esforço real está contido (trocar a leitura por uma que aceita os dois formatos, não reconstruir o resto do fluxo). Ambos os formatos já carregam o arquivo inteiro na memória pra processar — mesmo comportamento que o `DataImportJob` já tem hoje com CSV, então não é um risco novo.

**Validação prévia (pré-voo), antes de disparar qualquer mensagem:** todas as variáveis obrigatórias do template mapeadas, nenhuma célula obrigatória vazia, contagem de destinatários e estimativa de tempo (dado o rate limit) — mostrado ao operador antes de confirmar, não descoberto no meio do processamento.

### 4. Mapeamento de colunas → variáveis do template

Depois de escolher o template (a UI já sabe quais variáveis ele exige — é o que `WhatsAppTemplateParser.vue` já lista hoje), ler o cabeçalho da planilha e:
- **Sugerir automaticamente** pareamento por nome parecido (`vencimento` → variável `vencimento`), sempre com **confirmação manual** do operador antes de disparar (um dropdown por variável: "qual coluna usar?").
- Coluna de telefone identificada por nome comum (`telefone`, `phone`, `numero`) ou, na dúvida, perguntada explicitamente — nunca adivinhada às cegas.

### 5. Tratamento de erros

Mesmo padrão que o import de contato já usa e que funciona bem: linha inválida (telefone vazio/mal formatado, variável obrigatória do template vazia) cai numa lista de "rejeitados" com o motivo, empacotada em CSV pra download — igual ao `failed_records` do `DataImport` hoje.

**O que precisa ser construído do zero** (não existe pra nenhuma campanha hoje, nem WhatsApp nem SMS): um **relatório pós-envio** — quantos enviados, quantos falharam e por quê (template rejeitado pela Meta, número inválido, rate limit). Hoje isso só existe como log de servidor, invisível pro operador.

Duplicidade de telefone dentro da própria planilha: manter a primeira ocorrência e reportar as demais como "duplicada" no relatório de rejeitados.

### 6. Menos passos possível — Assistente de Campanha (wizard)

1. Escolher o template aprovado (a UI já mostra quais variáveis ele pede).
2. Upload da planilha (CSV ou XLSX).
3. Confirmar o mapeamento coluna → variável (sugerido automaticamente por nome parecido, editável).
4. **Validação prévia**: variáveis obrigatórias todas mapeadas? células vazias? quantos destinatários, quanto tempo estimado?
5. Prévia renderizada de 2-3 linhas reais da planilha (isso hoje não existe — é a melhora de UX mais visível pro operador).
6. Disparar (ou agendar) — processado em lotes, com rate limit.
7. Relatório final: quantos enviados, quantos falharam e por quê, planilha de rejeitados pra baixar.

---

## Decisões já resolvidas nesta revisão

- **CSV e XLSX** desde a primeira versão.
- **Sem `Contact` obrigatório.** O disparo tem sua própria tabela de destinatários (telefone + variáveis da linha + status). Quem nunca responde nunca vira contato; quem responde, o webhook de entrada já resolve sozinho (comportamento nativo, nada a construir).
- **Sem etiqueta nenhuma.** Consequência do item acima — a audiência do disparo são as próprias linhas da sua tabela de destinatários, não precisa de `Label` pra isolar quem faz parte de qual envio.

## Próximo passo sugerido

Escrever o plano de implementação (models, migrations, jobs, telas) no mesmo formato que fizemos para o bot do Captain.

---

## Revisão (14/07/2026) — segunda opinião de outra IA

O usuário levou esta análise pra outra IA e trouxe 7 pontos + a ideia do wizard. Registro aqui o que mudou de fato e o que já estava coberto, pra não perder o porquê de cada decisão:

**Mudou a arquitetura (a outra IA estava certa, eu incompleto):**
- **Contato obrigatório** — eu tinha escrito que "toda mensagem do WhatsApp pressupõe um Contact/Conversation por trás". Falso pro caminho de campanha: `channel.send_template(phone, template_info, nil)` já roda hoje sem criar nenhum registro local (`process_response`/`handle_error` só fazem algo com o `message` se ele não for `nil`) — `Contact` só era necessário porque é o jeito de consultar "quem tem essa etiqueta", não uma exigência do envio em si. Verificado lendo `app/services/whatsapp/providers/whatsapp_cloud_service.rb` e `base_service.rb` antes de aceitar o ponto.
- **Etiqueta automática** — deixou de ser "esconder do operador" pra "não precisa existir", consequência direta do ponto acima.
- **XLSX desde já** — eu tinha sugerido adiar; aceito que o custo é baixo (gem `roo`) e a serventia (operador não precisa converter manualmente) é real.
- **Validação prévia** — eu só tinha a prévia de conteúdo; faltava checar cobertura de variável/células vazias/estimativa antes de começar a processar.

**Já estava coberto, só não com destaque:**
- Deduplicação de telefone repetido na planilha — já estava na seção de tratamento de erros.
- Processamento em lotes (não um `.each` só) — já era a recomendação do ponto 2 original.
- "Módulo separado por trás, tela unificada pro usuário" — já era exatamente a proposta original do ponto 1; a "discordância" descrevia a mesma coisa.
- O wizard é a mesma sequência de passos já proposta, com nome e desenho de UI — bom de adotar como especificação de componente, não é mudança de arquitetura.
