# Fluxo de Atendimento — WhatsApp (Bot de Triagem)

Bot de triagem para o canal WhatsApp Cloud API integrado ao Chatwoot.  
Construído no Typebot: https://bot.mobillirentals.com.br

---

## Diagrama

```mermaid
graph TD
    %% Nós Principais
    Inicio([Início]) --> Expediente{Horário de Atendimento?}

    %% Fora do Expediente
    Expediente -- Fora do Horário --> ForaExpediente[Mensagem: Fora do Expediente / Horários]

    %% Dentro do Expediente
    Expediente -- Dentro do Horário --> Saudacao[Mensagem: Saudação Mobílli]
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
    class Expediente,Setor,Fin_Assunto,Ajuda_Setor,Of_Assunto,Duv_Assunto,Ouv_Assunto,Soc_Setor decisao;
    class ForaExpediente,Saudacao,Of_Link,Ouv_Den,Ouv_Rec,Soc_Msg,Roubo_Msg mensagem;
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
