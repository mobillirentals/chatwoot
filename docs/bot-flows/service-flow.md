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
    Nome --> Setor{Como posso ajudar?}

    %% Financeiro
    Setor -- 💳 Financeiro / Cobranças --> Fin_Assunto{Qual o assunto?}
    Fin_Assunto -- Mensalidade / Multas / Franquias --> Transf_Fin[Transferir: Fin. Contas a Receber]
    Fin_Assunto -- Fornecedores --> Transf_Forn[Transferir: Grupo Geral]

    %% Veículo / Manutenção
    Setor -- 🔧 Veículo / Manutenção --> Veiculo_Assunto{O que precisa?}
    Veiculo_Assunto -- Agendar revisão --> Link_Revisao[Mensagem: Link de Agendamento] --> Encerrar[Encerrar Conversa]
    Veiculo_Assunto -- Falar com atendente --> Transf_Manut[Transferir: Manutenção]

    %% Documentos e Contratos
    Setor -- 📋 Documentos e Contratos --> Doc_Assunto{Qual o assunto?}
    Doc_Assunto -- Documentos para locar --> Doc_Self[Self-service: CNH + CPF + Cartão de crédito]
    Doc_Self --> Doc_Mais{Ficou alguma dúvida?}
    Doc_Mais -- Não --> Encerrar
    Doc_Mais -- Sim --> Transf_Frota[Transferir: Frota - Multas e Doc.]
    Doc_Assunto -- Multas de trânsito --> Transf_Frota
    Doc_Assunto -- Dúvidas contratuais --> Transf_PosVenda[Transferir: Pós-Venda]

    %% Emergência
    Setor -- 🆘 Emergência --> Emerg_Tipo{Qual a situação?}
    Emerg_Tipo -- Socorro / Acidente --> Coleta[Coleta: Nome + Placa + Localização + Referência] --> Transf_Socorro[Transferir: Socorro]
    Emerg_Tipo -- Furto / Roubo --> Msg_Roubo[Mensagem: Alerta + BO] --> Transf_Sinistro[Transferir: Sinistro]

    %% Ouvidoria
    Setor -- 📣 Ouvidoria --> Ouv_Texto[Coleta: Descreva sua mensagem]
    Ouv_Texto --> Transf_Ouv[Transferir: Ouvidoria]

    %% Filas
    Transf_Fin --> Fila[Fila: Aguardar Atendente]
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
    class Setor,Fin_Assunto,Veiculo_Assunto,Doc_Assunto,Emerg_Tipo,Doc_Mais decisao;
    class Saudacao,Nome,Link_Revisao,Msg_Roubo,Coleta mensagem;
    class Doc_Self,Ouv_Texto selfservice;
    class Transf_Fin,Transf_Forn,Transf_Manut,Transf_Frota,Transf_PosVenda,Transf_Socorro,Transf_Sinistro,Transf_Ouv transferencia;
    class Encerrar encerrar;
```

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

## Pendências

- [ ] Confirmar se todos os Times acima existem no Chatwoot
- [ ] Definir mensagem de fila de espera padrão (usada em todos os transfers)
- [ ] Definir coleta de nome: antes do menu ou por setor?
- [ ] Confirmar que Furto/Roubo não coleta dados antes de transferir
- [ ] Integrar Typebot ↔ Chatwoot via Agent Bot webhook
