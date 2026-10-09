# Destrave de Features Premium (Enterprise) — Status

> **Completo e estável.** Todas as features Enterprise destravadas no self-hosted, sem paywall e sem auto-desligamento. **01/10/2026:** a marca da casa entrou na mesma conta — ver a seção logo abaixo.

## 01/10/2026 — faltava uma terceira lista: a da MARCA (PR #113)

O mesmo `Internal::ReconcilePlanConfigService` lê **duas** listas, e o PR #37 esvaziou só a das
features. A outra é `enterprise/config/premium_installation_config.yml`, com as chaves de marca
(`INSTALLATION_NAME`, `BRAND_NAME`, `BRAND_URL`, `WIDGET_BRAND_URL`, logos, termos): no plano
`community` o job reescrevia todas de volta para os valores do Chatwoot.

Era isto que desfazia a marca da casa — o mistério que ficou anotado como "gatilho não
identificado" no deploy do upgrade. **Não era o deploy, era o relógio.** A prova veio do carimbo de
hora: as quatro chaves atualizadas no mesmo segundo, às **03:39 UTC**, sem ninguém mexendo.

Agora a lista está vazia, pela mesma razão da outra. Sem nada a reconciliar, o Super Admin volta a
ser a única fonte da marca.

⚠️ **Para conferir se voltou a acontecer**, é mais rápido olhar o `updated_at` do que o valor:

```ruby
InstallationConfig.find_by(name: 'INSTALLATION_NAME').then { |c| [c.value, c.updated_at] }
```

Horário de madrugada no `updated_at` = o job mexeu.

O spec do upstream (`spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb`)
afirmava o comportamento contrário nos dois lados. Os exemplos do bloco `community` passaram a
descrever o que este fork faz — e a falha que já existia ali desde o PR #37 sumiu junto: 7
exemplos, 0 falhas.

## 🔑 Descoberta-chave: o gating vive em DOIS pontos

Destravar feature por feature virava whack-a-mole. Solução (**PR #37**, ambos esvaziados para `[]`):

1. **Backend — `enterprise/config/premium_features.yml`**: `Internal::ReconcilePlanConfigService` (job 00:00 UTC) faz `account.disable_features!(*premium_features)` quando `ChatwootHub.pricing_plan == 'community'` — desligava a feature toda meia-noite, por mais que fosse habilitada.
2. **Frontend — `PREMIUM_FEATURES` em `app/javascript/dashboard/featureFlags.js`**: `usePolicy.shouldShowPaywall` mostra o paywall "Atualize seu plano" pra qualquer feature dessa lista quando `isEnterprise && enterprisePlanName === 'community'` — **independente da flag estar ligada**.

Com as duas listas vazias: sem paywall, sem auto-desligamento. Features seguem controladas só pela **feature flag normal por conta** (Super Admin → Contas → Features), que agora persiste.

## Terceira lista (só visual)

`app/helpers/super_admin/features.yml` — cadeado ↔ tique verde no `/super_admin/settings`, chumbado ao `pricing_plan`. **Não afeta funcionamento** (cards sem `config_key` não têm ação). Lido a cada request (`File.read` + ERB) → aceita hot-patch sem restart.

**⚠️ Lição (já quebrou produção):** ao hot-patchar esse arquivo, **copiar o arquivo inteiro** (`cat >`), **nunca `sed`/regex** — um `.*` guloso com flag multiline já casou do `enabled:` de um item até o fim do arquivo e truncou 20 cards.

## Estado final (verificado)

- `enterprise/config/premium_features.yml` = `[]` · `PREMIUM_FEATURES` = `[]`
- Flags ON: `audit_logs`, `captain_integration`, `captain_integration_v2`, `custom_tools`, `sla`, `custom_roles`, `csat_review_notes`, `conversation_required_attributes`
- Opt-in, deixado OFF: `disable_branding` (removeria "Powered by Chatwoot")
- Banner "Unauthorized premium changes detected" no Super Admin é só o nag do próprio Chatwoot por usar premium em plano `community` — inofensivo.
