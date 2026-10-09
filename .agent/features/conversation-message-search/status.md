# Pesquisa dentro da conversa — Status

> **Em produção desde 25/09/2026** (PRs #102, #103 e #104). Nasceu do histórico importado, onde
> uma conversa chega a milhares de mensagens, mas vale para qualquer conversa da plataforma.

## O que é

Item **"Pesquisar na conversa"** no menu de três pontos do cabeçalho, abrindo um painel à direita
com **dois modos que não se misturam**:

- **Texto** — lista os resultados (remetente, data, conteúdo); clicar leva até a mensagem no fio.
- **Período** — não devolve lista. O próprio fio passa a mostrar só o intervalo, com aviso no topo
  e "limpar". Rolar para cima continua carregando dentro do período.

A separação em dois modos foi pedido do usuário depois de ver a primeira versão: um formulário só,
com texto e datas juntos, devolvendo lista para os dois casos, "fica meio fora de UX" — para ver
junho a pessoa quer **ler a conversa daquele mês**, não um relatório dela.

## Arquivos-chave

- `app/finders/message_finder.rb` — ganhou `q`, `since` e `until`. Usa o índice de
  `conversation_id` e filtra só o que pertence à conversa: num fio de 5.270 mensagens sai em
  milissegundos (medido em produção). "Até 31/12" inclui o dia inteiro.
- `app/javascript/dashboard/components/widgets/conversation/MessageFilterPanel.vue` — o painel.
- `MessagesView.vue` — filtro de período no fio, realce e o "ir até a mensagem".
- `ConversationView.vue` — estado do painel e coordenação com Contato/Copilot.
- `dashboard/store/modules/conversations/actions.js` — `fetchMessagesByPeriod` e
  `reloadLatestMessages`.
- `dashboard/api/inbox/message.js` — `filtrar(...)`.

## Decisões que valem lembrar

**O painel é irmão dos painéis nativos** (Contato e Copilot), no `ConversationView` — não filho do
`ConversationBox`. Dentro do Box, o comutador flutuante (`SidepanelSwitch`, que é `absolute` na
borda direita) passava **por cima** do painel. Os painéis nativos são irmãos justamente por isso.
Usa as mesmas classes de largura e de responsivo do `ConversationSidebar`.

**Um painel de cada vez.** Abrir a pesquisa fecha Contato/Copilot (via `updateUISettings`) e
devolve o estado ao fechar; abrir Contato/Copilot fecha a pesquisa **sem** restaurar — a escolha
acabou de ser do usuário, restaurar a desfaria.

**O modo Texto não mexe na store; o modo Período mexe.** O texto faz consulta própria e só lista.
O período substitui a lista de mensagens da conversa (`SET_MISSING_MESSAGES`) e o render filtra por
data. Foi decisão consciente: filtrar o fio é o que a UX pedia, e o risco fica contido (trocar de
conversa limpa, "limpar" recarrega a janela normal).

**O realce mora no mecanismo nativo** (`onScrollToMessage`), então vale também para clique em
resposta citada e para a busca global. Respeita `prefers-reduced-motion`. O CSS ficou dentro do
`MessagesView.vue`, sem escopo — ver gotcha do `scss-lint` em `.ai/workflow.md`.

## Dois defeitos reais encontrados no caminho (não eram da feature)

1. **Lista filtrada pedia página sem fim** (PR #102). Com uma caixa de 33 mil conversas, a rolagem
   chamava `/conversations/filter?page=N` sem parar — 121 requisições e 25 MB numa abertura. Duas
   causas somadas: `conversationPage.hasEndReached` **não tinha a chave `appliedFilters`** (o
   getter devolvia `undefined`, falso para sempre), e o fim só era marcado quando uma página
   voltava **vazia** — nessa caixa, a página 1.320. Agora também para quando o total carregado
   alcança o `all_count` do `meta`.
2. **"Ir até a mensagem" rolava antes de carregar** (PR #104). O código rolava e só depois buscava
   as anteriores, inserindo conteúdo acima no meio da animação — e ainda forçava o `scrollTop` com
   uma posição lida pela metade. A mensagem alvo saía do lugar. Agora carrega, pega o elemento de
   novo (a lista pode ter sido redesenhada) e só então rola, com `block: 'center'`.

## Linha do tempo

- **PR #102** (25/09): primeira versão do painel + os dois parâmetros no `MessageFinder` + correção
  da paginação infinita + caixa de histórico abrindo com status "Todos".
- **PR #103**: clicar no resultado leva até a mensagem (usa `fetchPreviousMessages` com `after` e
  `BUS_EVENTS.SCROLL_TO_MESSAGE`, o mesmo caminho da busca global) + responsividade. Este commit
  **orfanou** — foi empurrado depois do merge da #102 (mesmo padrão já visto em
  `conversation-export-pdf`: sempre conferir `gh pr view` antes de empurrar mais commits).
- **PR #104**: reescrita em dois modos, realce, centralização, carga antes da rolagem, painel
  movido para irmão dos nativos, coordenação com Contato/Copilot, `list-none` na lista de
  resultados (o estilo base do projeto desenha marcador em toda `ul`).

## Pendências conhecidas

- **A busca global (a lupa do topo) continua limitada a 3 meses** — `SearchService#message_base_query`
  tem `where('created_at >= ?', 3.months.ago)` fixo. Ela não enxerga o histórico importado. Não foi
  mexido: com 1 milhão de mensagens, vale medir antes.
- Não há teste automatizado da feature; a validação foi manual no ambiente local, numa conversa
  semeada com 900 mensagens espalhadas por mais de um ano.
