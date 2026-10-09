# Criar, editar e apagar modelo de WhatsApp pela tela

**Estado:** em produção desde 08/10/2026 (PRs #131 e #134). A tela de `Configurações → Modelos`
só lia o que a sincronização trazia; criar ou mudar um modelo exigia abrir o painel da Meta,
preencher lá e voltar. Agora o ciclo inteiro acontece no Chatwoot.

O modelo continua vivendo **na Meta**, não no nosso banco — `message_templates` do canal é só um
espelho. Por isso toda operação sincroniza no fim: sem isso a lista ficaria velha até a varredura
de 3 em 3 horas, e quem acabou de criar acharia que não funcionou.

## Por que as regras da Meta estão escritas no nosso código

Ela recusa o modelo **inteiro** por um detalhe de formato e devolve uma mensagem genérica, depois
de a pessoa ter preenchido tudo. Validar antes de enviar é a diferença entre "corrija o nome" e
"algo deu errado". As regras ficam nos dois lados — `composeTemplate.js` (conveniência) e
`Whatsapp::TemplateManagementService` (de verdade):

| Regra | Como aparece na tela |
|---|---|
| Nome só aceita `[a-z0-9_]` | normalizado enquanto digita, como a Meta faz no painel dela |
| Variáveis sequenciais a partir de 1 | inseridas no cursor, nunca digitadas à mão |
| Corpo não pode começar nem terminar com variável (*dangling parameter*) | barrado nos dois lados |
| Rodapé não aceita variável; cabeçalho aceita no máximo uma | barrado nos dois lados |
| Um exemplo por variável | campo próprio, obrigatório |

**Sobre os exemplos:** eles são o que o analista da Meta lê para entender o modelo. Um `exemplo 1`
genérico passa na validação de formato mas **pesa contra a aprovação**, então quem cria escreve o
valor real — e a prévia usa esse valor em vez de mostrar `{{1}}`.

## Limites da Meta, confirmados na documentação oficial

- Editar: **10 vezes em 30 dias, 1 a cada 24 h**. Só `APPROVED`, `REJECTED` ou `PAUSED` são
  editáveis; rejeitado e pausado têm edições ilimitadas.
- Modelo aprovado editado é **reaprovado automaticamente** — não volta para análise. (A tela dizia
  o contrário antes de eu conferir na documentação.)
- **Categoria de aprovado não pode mudar**, por isso ela não vai no corpo do `update`.
- Apagar é definitivo e a Meta **segura o nome por 30 dias**.

## O que a tela se recusa a editar, de propósito

Editar reenvia o modelo inteiro, então o que a tela não sabe remontar seria **apagado no caminho**.
Nesses casos ela bloqueia e manda para o painel da Meta: cabeçalho de mídia, botão de ligar /
copiar código / Flow, categoria legada (`TRANSACTIONAL`, `OTP`), autenticação, e modelo ainda em
análise.

Apagar não tem essa restrição — não há nada para remontar, então vale para qualquer modelo da
Cloud. A confirmação mostra o nome do modelo no título: a lista some atrás do diálogo, e sem isso
a pessoa confirma sem ver qual dos 23 está prestes a apagar.

**Fora do alcance, de propósito:** catálogo, Flows, pagamento e compartilhar contato continuam no
painel da Meta. Oferecer na tela e falhar no envio seria pior do que não oferecer.

## Armadilhas registradas

⚠️ **`WHATSAPP_CLOUD_BASE_URL` no `.env` vaza para os specs.** Derrubou os testes do recado de voz
sem ser regressão nenhuma — eles fixam `graph.facebook.com` e a variável apontava para outro lugar.
Spec dessa área precisa stubar o ENV.

⚠️ **O upstream fixa `v14.0`** em `business_account_path` (leitura/sincronização), enquanto a escrita
usa a versão configurável (`v22.0`). As duas funcionam na Meta; não foi alterado.

⚠️ **A Meta reclassifica a categoria na análise.** Um modelo criado como Utilidade pode virar
Marketing se o conteúdo não se ligar a algo que o cliente pediu — e marketing custa mais por envio.
A lista mostra a categoria efetiva depois da sincronização, não a escolhida.

## Onde mexer

| | |
|---|---|
| Serviço | `app/services/whatsapp/template_management_service.rb` |
| Ações | `enterprise/app/controllers/enterprise/api/v1/accounts/inboxes/message_template_actions.rb` |
| Regras no navegador | `app/javascript/dashboard/routes/dashboard/settings/templates/composeTemplate.js` |
| Marcação do WhatsApp | `.../templates/whatsappMarkup.js` |
| Tela | `.../templates/Editor.vue`, `TemplateBubblePreview.vue`, `ConfirmDeleteTemplateDialog.vue` |

O concern das ações fica **no corpo** do módulo enterprise, não em `included do`: o módulo é
*prepended* no controller, e o bloco `included` do `ActiveSupport::Concern` não dispara em prepend —
as ações sumiriam em silêncio.

## Pendente

- **Webhook `message_template_status_update`**: ninguém escuta. O status de um modelo criado só
  atualiza no botão de sincronizar ou na varredura de 3 h.
