# Fluxo de Atendimento — WhatsApp (Bot de Triagem)

Bot de triagem para o canal WhatsApp Cloud API integrado ao Chatwoot.  
Construído no Typebot: https://bot.mobillirentals.com.br

---

## Fluxo v2 — Proposta Otimizada

### Mudanças em relação ao v1

| # | Problema | Solução |
|---|---|---|
| 1 | Até 4 níveis de menu antes do atendente | Máximo 2 níveis em qualquer caminho |
| 2 | "Ajuda" agrupa categorias sem relação | Substituído por "Veículo / Manutenção" e "Documentos e Contratos" |
| 3 | Sem coleta de nome | Nome coletado logo após a saudação |
| 4 | Tudo termina em transferência | Documentação e agendamento resolvidos sem atendente |
| 5 | Mensalidade e Multas/Franquias duplicadas | Unificadas em "Cobranças" (mesmo destino) |
| 6 | Ouvidoria com 3 sub-opções pro mesmo time | Campo de texto livre → transfer direto |

```mermaid
graph TD
    Inicio([Início]) --> Saudacao[Mensagem: Saudação Mobílli]
    Saudacao --> Nome[Coleta: Qual o seu nome?]
    Nome --> Menu{Como posso ajudar?}

    %% ── Nível 1: 3 botões ────────────────────────────────────
    Menu -- 💰 Financeiro --> Fin_Assunto{Qual o assunto?}
    Menu -- 🤝 Atendimento --> Atend_Setor{Qual o setor?}
    Menu -- 🆘 Emergência --> Emerg_Tipo{Qual a situação?}

    %% ── Financeiro: 2 botões ─────────────────────────────────
    Fin_Assunto -- Cobranças --> Transf_Fin[Transferir: Fin. Contas a Receber]
    Fin_Assunto -- Fornecedores --> Transf_Forn[Transferir: Grupo Geral]

    %% ── Atendimento: 3 botões ────────────────────────────────
    Atend_Setor -- 🔧 Veículo / Oficina --> Veiculo_Assunto{O que precisa?}
    Atend_Setor -- 📋 Documentos e Dúvidas --> Doc_Assunto{Qual o assunto?}
    Atend_Setor -- 📣 Ouvidoria --> Ouv_Texto[Coleta: Descreva sua mensagem]

    %% Veículo: 2 botões
    Veiculo_Assunto -- Agendar revisão --> Link_Revisao[Mensagem: Link de Agendamento]
    Link_Revisao --> Wait2min[Aguardar 2 minutos]
    Wait2min --> Pos_Link{Posso ajudar com mais alguma coisa?}
    Pos_Link -- Sim --> Menu
    Pos_Link -- Não --> Despedida[Mensagem: Despedida] --> Encerrar[Encerrar]
    Veiculo_Assunto -- Falar com atendente --> Transf_Manut[Transferir: Manutenção]

    %% Documentos: 3 botões
    Doc_Assunto -- Docs para locar --> Doc_Self[Self-service: CNH + CPF + Cartão]
    Doc_Self --> Wait_Doc[Aguardar 2 minutos]
    Wait_Doc --> Doc_Mais{Ficou alguma dúvida?}
    Doc_Mais -- Não --> Despedida
    Doc_Mais -- Sim --> Transf_Frota[Transferir: Frota - Multas e Doc.]
    Doc_Assunto -- Multas de trânsito --> Transf_Frota
    Doc_Assunto -- Dúvidas contratuais --> Transf_PosVenda[Transferir: Pós-Venda]

    %% Ouvidoria: texto livre
    Ouv_Texto --> Transf_Ouv[Transferir: Ouvidoria]

    %% ── Emergência: 2 botões ─────────────────────────────────
    Emerg_Tipo -- Socorro / Acidente --> Coleta[Coleta: Placa + Localização + Referência] --> Transf_Socorro[Transferir: Socorro]
    Emerg_Tipo -- Furto / Roubo --> Msg_Roubo[Mensagem: Alerta + BO] --> Transf_Sinistro[Transferir: Sinistro]

    %% ── Fila de espera ───────────────────────────────────────
    Transf_Fin --> Fila[Fila: Aguardar Atendente]
    Transf_Forn --> Fila
    Transf_Manut --> Fila
    Transf_Frota --> Fila
    Transf_PosVenda --> Fila
    Transf_Socorro --> Fila
    Transf_Sinistro --> Fila
    Transf_Ouv --> Fila

    %% Estilização
    classDef inicio fill:#ff8b1a,stroke:#333,stroke-width:2px,color:#fff;
    classDef decisao fill:#fff,stroke:#333,stroke-width:2px;
    classDef mensagem fill:#f9f9f9,stroke:#333,stroke-width:1px;
    classDef selfservice fill:#d4edda,stroke:#28a745,stroke-width:1px;
    classDef transferencia fill:#373a86,stroke:#333,stroke-width:1px,color:#fff;
    classDef encerrar fill:#6c757d,stroke:#333,stroke-width:1px,color:#fff;

    class Inicio inicio;
    class Menu,Fin_Assunto,Atend_Setor,Veiculo_Assunto,Doc_Assunto,Emerg_Tipo,Doc_Mais decisao;
    classDef espera fill:#fff3cd,stroke:#ffc107,stroke-width:1px;
    class Saudacao,Nome,Link_Revisao,Msg_Roubo,Coleta,Despedida mensagem;
    class Wait2min,Wait_Doc espera;
    class Doc_Self,Ouv_Texto selfservice;
    class Transf_Fin,Transf_Forn,Transf_Manut,Transf_Frota,Transf_PosVenda,Transf_Socorro,Transf_Sinistro,Transf_Ouv transferencia;
    class Encerrar encerrar;
```

### Regra de botões WhatsApp

| Nível | Menu | Botões | OK? |
|---|---|---|---|
| 1 | Menu principal | 3 (Financeiro / Atendimento / Emergência) | ✅ |
| 2 | Financeiro | 2 (Cobranças / Fornecedores) | ✅ |
| 2 | Atendimento | 3 (Veículo / Documentos / Ouvidoria) | ✅ |
| 2 | Emergência | 2 (Socorro-Acidente / Furto-Roubo) | ✅ |
| 3 | Veículo | 2 (Agendar / Atendente) | ✅ |
| 3 | Documentos | 3 (Docs / Multas / Contrato) | ✅ |
| 3 | Ouvidoria | texto livre | ✅ |

---

## Fluxo v1 — Original

> **Nota:** O controle de horário de atendimento é gerenciado nativamente pelo Chatwoot  
> (Configurações → Horário de Funcionamento). O Typebot só é acionado dentro do horário.

## Diagrama

> **Nota:** O controle de horário de atendimento é gerenciado nativamente pelo Chatwoot  
> (Configurações → Horário de Funcionamento). O Typebot só é acionado dentro do horário.

```mermaid
graph TD
    %% Nós Principais
    Inicio([Início]) --> Saudacao[Mensagem: Saudação Mobílli]
    Saudacao --> Setor{🤔 Qual setor deseja?}

    %% Subfluxo: Financeiro
    Setor -- Financeiro --> Fin_Assunto{Qual o assunto?}
    Fin_Assunto -- Mensalidade --> Transf_Fin_Receber[Transferir: Fin. Contas a Receber]
    Fin_Assunto -- Multas e Franquias --> Transf_Fin_Franquia[Transferir: Fin. Contas a Receber]
    Fin_Assunto -- Fornecedores --> Transf_Fin_Forn[Transferir: Grupo Geral]

    %% Subfluxo: Ajuda
    Setor -- Ajuda --> Ajuda_Setor{Qual o setor?}

    Ajuda_Setor -- Oficina --> Of_Assunto{Qual o assunto?}
    Of_Assunto -- Marcar Revisão --> Of_Link[Mensagem: Link de Agendamento] --> Encerrar_Of[Encerrar Conversa]
    Of_Assunto -- Falar com Atendente --> Transf_Manutencao[Transferir: Manutenção]

    Ajuda_Setor -- Dúvidas --> Duv_Assunto{Qual o assunto?}
    Duv_Assunto -- Multas de Trânsito --> Transf_Frota[Transferir: Frota - Multas e Doc.]
    Duv_Assunto -- Dúvidas Contratuais --> Transf_PosVenda1[Transferir: Pós-Venda]
    Duv_Assunto -- Documentos --> Transf_Frota2[Transferir: Frota - Multas e Doc.]

    Ajuda_Setor -- Ouvidoria --> Ouv_Assunto{Qual o assunto?}
    Ouv_Assunto -- Denúncia --> Ouv_Den[Mensagem: Sigilo] --> Transf_Ouv1[Transferir: Ouvidoria]
    Ouv_Assunto -- Reclamações --> Ouv_Rec[Mensagem: Coleta de Dados] --> Transf_Ouv2[Transferir: Ouvidoria]
    Ouv_Assunto -- Sugestões --> Transf_Ouv3[Transferir: Ouvidoria]

    %% Subfluxo: Socorro/Sinistro
    Setor -- Socorro/Sinistro --> Soc_Setor{Qual o setor?}

    Soc_Setor -- Socorro --> Soc_Msg[Mensagem: Termos e Cobertura] --> Coleta_Dados[Coleta: Nome, Placa, Localização e Ref.] --> Transf_Socorro[Transferir: Socorro]

    Soc_Setor -- Acidente --> Coleta_Dados

    Soc_Setor -- Furto/Roubo --> Roubo_Msg[Mensagem: Alerta Inteligência + BO] --> Transf_Sinistro[Transferir: Sinistro]

    %% Filas de Espera
    Transf_Fin_Receber --> Wait_Fin[Fila: Aguardar Atendente]
    Transf_Manutencao --> Wait_Manut[Fila: Aguardar Atendente]
    Transf_Socorro --> Wait_Soc[Fila: Aguardar Atendente]
    Transf_Sinistro --> Wait_Sin[Fila: Aguardar Atendente]

    %% Estilização
    classDef inicio fill:#ff8b1a,stroke:#333,stroke-width:2px,color:#fff;
    classDef decisao fill:#fff,stroke:#333,stroke-width:2px;
    classDef mensagem fill:#f9f9f9,stroke:#333,stroke-width:1px;
    classDef transferencia fill:#373a86,stroke:#333,stroke-width:1px,color:#fff;

    class Inicio inicio;
    class Setor,Fin_Assunto,Ajuda_Setor,Of_Assunto,Duv_Assunto,Ouv_Assunto,Soc_Setor decisao;
    class Saudacao,Of_Link,Ouv_Den,Ouv_Rec,Soc_Msg,Roubo_Msg mensagem;
    class Transf_Fin_Receber,Transf_Fin_Franquia,Transf_Fin_Forn,Transf_Manutencao,Transf_Frota,Transf_PosVenda1,Transf_Frota2,Transf_Ouv1,Transf_Ouv2,Transf_Ouv3,Transf_Socorro,Transf_Sinistro transferencia;
```

---

## Times Chatwoot mapeados

| Rota do bot | Team no Chatwoot |
|---|---|
| Financeiro → Mensalidade / Multas e Franquias | Fin. Contas a Receber |
| Financeiro → Fornecedores | Grupo Geral |
| Ajuda → Oficina → Atendente | Manutenção |
| Ajuda → Dúvidas → Multas de Trânsito / Documentos | Frota - Multas e Doc. |
| Ajuda → Dúvidas → Contratuais | Pós-Venda |
| Ajuda → Ouvidoria | Ouvidoria |
| Socorro / Acidente | Socorro |
| Furto / Roubo | Sinistro |

---

---

## Integração CRM — Autoatendimento

O Typebot tem acesso a dados reais do cliente via um endpoint proxy no Chatwoot:

```
GET https://chat.mobillirentals.com.br/webhooks/crm/client_profile
    ?phone={{phoneNumber}}
    &token={{CRM_PROXY_TOKEN}}
```

### Resposta (JSON)

```json
{
  "found": true,
  "name": "WINSTON LUIZ LIMA DE ARAUJO",
  "first_name": "WINSTON",
  "cpf": "19077917799",
  "asaas_id": "cus_000173810998",
  "active_contract": true,
  "deal_id": "37536",
  "deal_start": "20/04/2026",
  "motorcycle_plate": "TOR8F68",
  "motorcycle_model": "GW12",
  "overdue_count": 2,
  "overdue_total": 552.00,
  "overdue_payments": [
    { "value": 276.0, "due_date": "10/05/2026", "invoice_url": "https://www.asaas.com/i/..." }
  ],
  "next_payment": { "value": 276.0, "due_date": "17/05/2026", "invoice_url": "https://..." }
}
```

### Casos de autoatendimento possíveis (sem humano)

| Pergunta do cliente | Variável usada | Resposta |
|---|---|---|
| "Quero pagar minha parcela" | `next_payment.invoice_url` | Link direto Asaas |
| "Tenho parcelas em atraso?" | `overdue_count`, `overdue_total` | "Sim, X parcela(s) — R$ Y" |
| "Qual minha moto?" | `motorcycle_plate`, `motorcycle_model` | "Placa TOR8F68 — GW12" |
| "Quando começou minha locação?" | `deal_start` | "20/04/2026" |
| "Estou em dia?" | `overdue_count == 0` | "Sim, você está em dia ✅" |

### Variáveis do Typebot

| Variável | Origem | Descrição |
|---|---|---|
| `phoneNumber` | `prefilledVariables` (Chatwoot) | Telefone do contato em formato E.164 |
| `conversationId` | `prefilledVariables` (Chatwoot) | ID da conversa no Chatwoot |
| `accountId` | `prefilledVariables` (Chatwoot) | ID da conta no Chatwoot |
| `chatwootToken` | `prefilledVariables` (Chatwoot) | Token do agent bot para webhooks |
| `clientName` | `prefilledVariables` (Chatwoot) | Nome do contato no Chatwoot |
| `crmData` | HTTP block (CRM proxy) | Objeto JSON com todos os dados do cliente |

---

## Pendências

- [x] Integrar Typebot ↔ Chatwoot via Agent Bot webhook
- [x] Confirmar que Furto/Roubo não coleta dados antes de transferir
- [ ] Implementar fluxo de autoatendimento financeiro no Typebot usando `crmData`
- [ ] Confirmar IDs dos times no Chatwoot (para os webhooks de assignment)
