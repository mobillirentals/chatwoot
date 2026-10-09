# Disparo em Massa via Planilha (WhatsApp) — Plano

> Status: **implementado e em produção** (7 PRs, ver `status.md`). Este arquivo é a arquitetura estável — não deveria mudar a cada sessão. Depende da análise em `analise.md` (decisões já fechadas: sem `Contact` obrigatório, sem etiqueta, CSV+XLSX desde já, tabela própria de destinatários).

## Visão geral

```
Frontend (Vue, wizard)              Backend (Rails)                       Externo
───────────────────────             ───────────────                       ───────
BulkDispatchWizard.vue         →    WhatsappBulkDispatchesController  →   WhatsApp Cloud API
  1. Template                        (create/update_mapping/confirm)       (Meta Graph)
  2. Upload planilha
  3. Mapear colunas              WhatsappBulkDispatch (model)
  4. Validação prévia              status: draft → processing → completed/failed
  5. Prévia renderizada            has_many :recipients
  6. Disparar/agendar
  7. Relatório                   WhatsappBulkDispatch::Recipient (model)
                                    phone_number, variables (jsonb), status, error

                                  Services (novos, mas em cima do que já existe):
                                    SpreadsheetReaderService  (CSV + XLSX → linhas)
                                    ColumnMapperService       (sugere coluna → variável)
                                    ValidationService         (pré-voo + dedup)
                                    PreviewService            (renderiza N linhas reais)
                                    DispatchService           (materializa recipients, dispara)

                                  Whatsapp::LiquidTemplateProcessorService
                                    (+ contexto novo "row", aditivo)

                                  Jobs:
                                    SendBatchJob (lote de 50, auto-reagenda até acabar)
                                    Rate limit via Redis::Alfred (contador por minuto)
```

**Ponto-chave que sustenta o plano inteiro:** `Whatsapp::TemplateProcessorService`, `Whatsapp::PopulateTemplateParametersService` e `Whatsapp::LiquidTemplateProcessorService` **não são amarrados ao model `Campaign`** — são serviços que recebem `channel`/`template_params`/um objeto pra renderizar Liquid. O disparo por planilha reaproveita esses três **sem tocar neles**, exceto uma adição pequena (contexto `row` no Liquid).

---

## Gotcha achado na planilha de exemplo original

Telefones no formato local, sem DDI, com espaços (`27 99670 2513`) — exatamente o formato que `DataImport::ContactManager#format_phone_number` (usado no import de contato) **trata errado**: só antepõe `+` se não começar com `+`, então viraria `+27 99670 2513` (código de país 27 = África do Sul, não DDD do Espírito Santo).

Normalizador certo já existia no projeto — `Crm::ClientProfileService#normalize_phone`:
```ruby
def normalize_phone(phone)
  phone = phone.to_s.gsub(/\D/, '')
  phone = "55#{phone}" unless phone.start_with?('55')
  "+#{phone}"
end
```
`SpreadsheetReaderService`/`ValidationService` do disparo usam **esta** lógica (assume Brasil, tira tudo que não é dígito, garante `55` na frente), não a do import de contato.

---

## Fase 1 — Backend

### 1.1 Migrations

```ruby
create_table :whatsapp_bulk_dispatches do |t|
  t.references :account, null: false
  t.references :inbox, null: false
  t.references :sender, foreign_key: { to_table: :users }
  t.string :title, null: false
  t.integer :status, default: 0, null: false # draft, processing, completed, failed
  t.string :template_name
  t.string :template_namespace
  t.string :template_language
  t.jsonb :column_mapping, default: {}       # { "1" => "nome", "__phone__" => "telefone" }
  t.datetime :scheduled_at
  t.integer :total_recipients, default: 0
  t.integer :sent_count, default: 0
  t.integer :failed_count, default: 0
  t.timestamps
end

create_table :whatsapp_bulk_dispatch_recipients do |t|
  t.references :whatsapp_bulk_dispatch, null: false
  t.string :phone_number, null: false
  t.jsonb :variables, default: {}
  t.integer :status, default: 0, null: false # pending, sent, failed
  t.string :error_message
  t.datetime :sent_at
  t.timestamps
end
add_index :whatsapp_bulk_dispatch_recipients, [:whatsapp_bulk_dispatch_id, :status]
add_index :whatsapp_bulk_dispatch_recipients, [:whatsapp_bulk_dispatch_id, :phone_number], unique: true
```

Sem `foreign_key: true` — o schema inteiro já segue esse padrão (`campaigns`, `data_imports`: index, sem constraint no banco). Sem `duplicate`/`invalid` no enum de `Recipient` — linhas rejeitadas/duplicadas nunca viram `Recipient`, só entram no relatório em memória (igual ao `DataImportJob`).

### 1.2 Models

`WhatsappBulkDispatch` — `belongs_to :account/:inbox`, `belongs_to :sender, class_name: 'User', optional: true`, `has_many :recipients`, `has_one_attached :file`, `has_one_attached :failed_rows`, enum de status, validação de inbox (só `Whatsapp` com `provider == 'whatsapp_cloud'`).

`WhatsappBulkDispatch::Recipient` — `belongs_to :whatsapp_bulk_dispatch`, enum de status.

### 1.3 Services

| Arquivo | Responsabilidade |
|---|---|
| `spreadsheet_reader_service.rb` | Detecta `.csv`/`.xlsx` pela extensão, devolve `{headers:, rows:}`. XLSX via gem `roo` (3.0.0); CSV via `CSV` padrão. |
| `column_mapper_service.rb` | Sugere mapeamento por nome parecido + tenta achar a coluna de telefone (`telefone`, `phone`, `numero`, `celular`, `whatsapp`, `fone`, `tel`). |
| `validation_service.rb` | Pré-voo: variável obrigatória sem mapeamento, célula obrigatória vazia, telefone ausente/inválido, duplicidade. Devolve `{valid_rows:, rejected_rows:, duplicate_count:, total:}`. |
| `preview_service.rb` | Renderiza as N primeiras `valid_rows` via `Whatsapp::LiquidTemplateProcessorService` de verdade — o texto **exatamente** como vai ser enviado. |
| `dispatch_service.rb` | Roda `ValidationService` de novo (nunca confia só no que rodou antes), bulk-insert dos `Recipient` válidos via `activerecord-import`, muda status pra `processing`, enfileira o primeiro `SendBatchJob`. |

### 1.4 Mudança aditiva no Liquid

`Whatsapp::LiquidTemplateProcessorService` — construtor aceita `row: nil` opcional; se presente, soma `'row' => row.transform_keys(&:to_s)` ao hash de `drops`. Campanha por etiqueta (fluxo nativo) nunca passa `row` — comportamento 100% preservado. `campaign:` aceito por duck typing (`Campaign` ou `WhatsappBulkDispatch`).

### 1.5 Job de envio

`SendBatchJob#perform(dispatch_id)`: lote de 50 (`BATCH_SIZE`), rate limit via `Redis::Alfred` (contador por inbox+minuto, `MAX_PER_MINUTE` configurável via `WHATSAPP_BULK_RATE_PER_MINUTE`), reagenda o job (não dorme a thread) se estourar o limite. Cada envio checa o `message_id` que `channel.send_template` devolve — **nunca confiar só em não ter lançado exceção** (ver gotcha em `status.md`, PR #60). Ao esgotar os `pending`: gera `failed_rows` (CSV), marca `completed`.

### 1.6 Controller + rotas

```ruby
resources :whatsapp_bulk_dispatches, only: [:index, :create, :show, :update, :destroy] do
  member { post :confirm }
end
```
- `create` — cria em `draft`, anexa arquivo, devolve headers + sugestão de mapeamento.
- `update` — grava `column_mapping`, revalida, devolve contagens + prévia renderizada.
- `confirm` — roda `DispatchService`, dispara de verdade.
- `show` — status + contadores + `recipients` (telefone, variáveis, status, erro) para o painel de detalhes.
- `index` — lista leve (sem `recipients`) para a listagem.
- `destroy` — só permitido enquanto o status não é terminal (regra fica no frontend; endpoint em si não valida isso).

---

## Fase 2 — Frontend

Diretório: `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/BulkDispatch/`. Decisão fechada: **uma tela pro usuário** (lista unificada com campanha por etiqueta), model separado por trás.

- `BulkDispatchWizard.vue` — wizard de 6 passos num único arquivo (template → upload → mapeamento → validação/prévia → confirmar → relatório com polling), não os 7 componentes separados do desenho original — mais simples de manter coeso.
- `BulkDispatchDetailsDialog.vue` — painel de detalhes (totais, progresso, filtro por status, destinatário a destinatário).
- `whatsappBulkDispatch.js` — cliente API, espelha `contacts.js#importContacts` (upload multipart via `FormData`); `get()`/`show()`/`delete()` herdados de `ApiClient`.

---

## Fase 3 — Verificação

1. Backend isolado via `rails runner` (CSV pequeno em memória, cada serviço na mão), sem envio real.
2. Rate limit: pré-encher o contador do Redis, confirmar reagendamento.
3. Envio de verdade: número de teste próprio, poucas linhas, nunca uma planilha real de clientes primeiro.
4. UI: planilha pequena de teste, wizard inteiro, conferir `recipients` no banco e relatório final.
5. Depois de qualquer mudança visual: **sempre verificar dentro do container** (não confiar só no ✅ do CI) — ver `.ai/workflow.md`.

---

## Mapa de arquivos

| Arquivo | Papel |
|---|---|
| `db/migrate/*_create_whatsapp_bulk_dispatch{es,_recipients}.rb` | Migrations |
| `app/models/whatsapp_bulk_dispatch.rb` (+ `/recipient.rb`) | Models |
| `app/services/whatsapp_bulk_dispatch/*.rb` | Os 5 services da Fase 1.3 |
| `app/services/whatsapp/liquid_template_processor_service.rb` | Modificado (aceita `row:`) |
| `app/jobs/whatsapp_bulk_dispatch/send_batch_job.rb` | Job de envio em lote |
| `app/controllers/api/v1/accounts/whatsapp_bulk_dispatches_controller.rb` | Controller |
| `app/policies/whatsapp_bulk_dispatch_policy.rb` | Admin-only |
| `app/views/api/v1/models/_whatsapp_bulk_dispatch.json.jbuilder` + `app/views/api/v1/accounts/whatsapp_bulk_dispatches/*.json.jbuilder` | Serialização |
| `config/routes.rb` | Rotas |
| `Gemfile` | `roo` (XLSX) |
| `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/BulkDispatch/*.vue` | Frontend |
| `app/javascript/dashboard/api/whatsappBulkDispatch.js` | Cliente API |
