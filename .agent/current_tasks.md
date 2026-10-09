# Tarefas Atuais

> **Índice**, não histórico completo. Cada linha aponta pra onde o contexto de verdade mora:
> - `features/<nome>/plan.md` — arquitetura estável de uma customização (escrito uma vez, quase não muda).
> - `features/<nome>/status.md` — log vivo daquela customização: PRs, achados, pendências.
> - `fixes-log.md` — tweaks/hotfixes pequenos que não têm pasta própria.
> - `archive/` — histórico fechado, sem relação com trabalho ativo (não precisa ler pra retomar contexto).
>
> Ao iniciar uma sessão: ler este índice, abrir só a(s) `status.md` da feature relevante. Ao terminar: atualizar a `status.md` da feature (não este arquivo, a menos que uma feature mude de ativa→estável ou surja uma nova).

## Última atualização: 06/10/2026

## Ativo agora

- **[[whatsapp-calling]]** (`features/whatsapp-calling/`) — **em teste em produção desde 06/10/2026**,
  só na caixa #1 "Whatsapp Testes - Oficial" (+55 27 99284-0261). Chamada de voz pelo WhatsApp:
  o cliente liga pela conversa, o atendente atende **no navegador** (WebRTC). Zero código nosso —
  é recurso do upstream v4.18.0 que estava com a feature `channel_voice` desligada. Duas armadilhas
  no `status.md`: (1) `enable_voice_calling!` manda **só** `calling.status` e deixa
  `call_icon_visibility` como `NOT_SET`, ou seja **o cliente não vê o botão de ligar** e nada
  acusa isso — tive que pôr `DEFAULT` na mão na Meta; (1b) o campo `calls` precisa ser assinado
  **também no app** (Meta for Developers → Webhooks), senão a Meta nem gera o evento: a ligação
  toca no celular do cliente e o Chatwoot nunca sabe que foi atendida. Não dá para ler isso por
  API sem app secret. **Validado nos dois sentidos depois disso** (3 chamadas completas);
  (2) as duas caixas oficiais dividem o
  **mesmo WABA** e `subscribed_fields` é assinatura do WABA, então ativar reescreve a do SAC — o
  upstream já protege (`calls_enabled_on_waba?` preserva `calls` dos irmãos) e o roteamento é por
  número, mas confirmei na hora que o SAC seguia recebendo. O SAC segue **desligado**. A caixa da
  ponte Baileys não suporta (exige `whatsapp_cloud`). Canal de Voz por Twilio continua sem
  nenhum canal configurado. Caminho de volta: `disable_voice_calling!`. **PR #124** (aberta,
  aguardando deploy): chamada do WhatsApp era gravada e **nunca transcrita** — o job só era
  enfileirado no caminho do Twilio, e o serviço lia só `call.recording`, que o WhatsApp não
  preenche (o áudio sobe como anexo da mensagem). ⚠️ A URL de callback **do app** é fixa no
  número de Testes — conferir isso antes de ligar voz no SAC.

- **[[whatsapp-nao-oficial]]** (`features/whatsapp-nao-oficial/`) — **em produção desde 06/10/2026**
  (PRs #121, #122 e #123), na caixa #11 "Whatsapp Comercial" (+55 27 98898-2141). Número fora da API da Meta, pareado por QR code, vira
  caixa de WhatsApp **de verdade**: BotFlow, CSAT, verificador e o fix do #117 valem nela sem
  adaptação, porque o provider entrou pelo ponto de extensão que o `BaseService` do upstream
  documenta. Atravessa texto, resposta citada e mídia nos dois sentidos, mais recibo de entrega e
  leitura; e faz duas coisas que **a API oficial não permite**: devolver o visto-azul e mostrar
  "digitando…". Tela própria de conexão (Caixas → WhatsApp → "WhatsApp por QR code") e, na caixa,
  estado da conexão + Reconectar com **trava de número**. ⚠️ Baileys contraria os termos da Meta: o
  número pode ser banido, sem recurso — número secundário, nunca o principal. O obstáculo central
  foi o **LID**, o identificador novo do WhatsApp que não contém o telefone — detalhes, as três
  armadilhas dele e as do ambiente → `status.md`.
- **Fila de pendentes zerada** (05/10/2026, operação, sem código) — as **5.162 conversas paradas
  há mais de 7 dias** foram encerradas sem disparar nada ao cliente: SQL direto nos quatro campos
  do resolve nativo, com rastro na etiqueta `limpeza-2026-10` e uma mensagem de atividade no
  histórico. Sobraram as 542 com movimento recente. Nenhuma pesquisa de satisfação saiu e nenhum
  job foi enfileirado (números iguais antes e depois). 94% do alvo eram **template disparado que o
  cliente nunca respondeu**, não atendimento abandonado. Receita, armadilhas (`taggings` não é
  idempotente por `ON CONFLICT`; a mensagem de atividade pelo caminho nativo apagaria o
  `last_activity_at`) e a conferência → `fixes-log.md`. ⚠️ **A fila volta a encher**: a causa é o
  volume de template, e a solução permanente é o que está parado em
  [[customer-inactivity-auto-resolve]].
- **Aprendizado do Captain quebrado desde o upgrade v4.18.0** — achado em 05/10/2026 ao levantar o
  risco da limpeza: **5.365 jobs mortos**, um por conversa resolvida, porque o upstream renomeou
  `generate_and_deduplicate` → `generate_suggestions` e o nosso listener não acompanhou. Pior que o
  nome: o listener chamava o serviço inline na fila `critical`, então a falha derrubava o evento
  inteiro e o `Captain::ReportingEventListener` nunca rodou. Corrigido no PR #119 (job próprio na
  fila `low`, primeiro spec do listener) — detalhes → `fixes-log.md`.
- **[[aparencia]]** (`features/aparencia/`) — **em produção desde 01/10/2026** (PR #111, sem
  migration). O item "Aparência" do menu do perfil deixou de abrir a barra de comandos (que só
  oferece claro/escuro/sistema) e passou a abrir tela própria com três escolhas que convivem: tema,
  **cor** da interface (seis, derivadas de matiz + saturação sobre a escala de claridade do tema em
  uso, com o realce caindo até contraste 4,5 com o branco) e **imagem de fundo da conversa** (13
  prontas ou a sua, reduzida no navegador antes de subir, 3 por pessoa com descarte da mais antiga
  no servidor). Nada é gravado até o Salvar, e a cada escolha o diálogo sai da frente por 1 s para
  a conversa aparecer. Quem não escolhe imagem vê a conversa exatamente como era. Pendente: sem
  testes do helper de cor — detalhes, armadilhas de CSS e o `<button>` que salvava sozinho →
  `status.md`.
- **[[tela-de-login]]** (`features/tela-de-login/`) — **em produção desde 28/09/2026** (PR #107). A
  tela de entrada ganhou foto de tela cheia (motoboy) com o bloco de login flutuando por cima,
  corte próprio para celular via `<picture>`, rodapé da Mobílli e queda do logo para os arquivos do
  repositório quando a instalação está sem `LOGO`. Junto veio o filtro de marca no i18n
  (`postTranslation`): o nome da instalação passa a valer nas 45 menções a "Chatwoot" que o
  `replaceInstallationName` nativo não alcança, sem editar arquivo de tradução — endereços e o
  código do widget ficam intactos, com 5 testes cobrindo isso. **Configuração de marca corrigida no
  banco de produção no mesmo dia**: `INSTALLATION_NAME` saiu de "Chatwoot" para **Chatmobilli**, e
  `BRAND_NAME`/`BRAND_URL`/`WIDGET_BRAND_URL` deixaram de apontar para o Chatwoot — detalhes →
  `status.md`.
- **[[historico-import]]** (`features/historico-import/`) — **concluído em 24–25/09/2026**. O
  histórico das plataformas anteriores (Octadesk e o WhatsApp do Underchat) vive agora numa caixa
  única `Histórico` (#9), com **uma conversa por pessoa**: 4.657 conversas, 1.026.046 mensagens e
  76.931 anexos (16,6 GB no Blob), de fev/2023 a ago/2026. O original ficou preservado no contêiner
  `arquivo-historico` da Azure, com a chave do backup no Key Vault e custódia no `suporte@`. Carga
  por `insert_all` (nada de ActiveRecord por registro), conversa importada nasce resolvida e já
  lida. Ferramentas em `lib/tasks/historico_import.rake` (`import`, `mover`, `juntar`, `midia`,
  `limpar`) — detalhes, decisões e tropeços → `plan.md`.
- **[[conversation-message-search]]** (`features/conversation-message-search/`) — **em produção
  desde 25/09/2026** (PRs #102–#104). "Pesquisar na conversa" no menu de três pontos, com dois
  modos que não se misturam: Texto lista resultados e leva até a mensagem (com realce); Período faz
  o próprio fio mostrar só o intervalo. Nasceu do histórico, serve para qualquer conversa. Levou
  junto dois defeitos reais da plataforma: lista filtrada que pedia página sem fim e "ir até a
  mensagem" que rolava antes de carregar — detalhes → `status.md`.

- **[[customer-inactivity-auto-resolve]]** (`features/customer-inactivity-auto-resolve/`) — ⏸️ EM
  STANDBY, só design discutido (27/08/2026), nada implementado. Espelho do
  [[unattended-conversation-alert]] pro lado do cliente: cliente some depois que o agente já
  respondeu → avisa em X, fecha automaticamente em X+Y. Achei que o Chatwoot nativo já tem metade
  disso (Auto Resolve, hoje desligado nesta conta) — só falta o estágio de aviso. Bloqueado
  esperando o usuário decidir os limiares X/Y e o texto das mensagens — detalhes → `status.md`.
- **[[unattended-conversation-alert]]** (`features/unattended-conversation-alert/`) — completo e
  estável em produção. PRs #88–#92 (26–27/08/2026): 3 camadas de alerta automático quando o agente
  responsável não responde (cliente avisado se o agente está ausente/offline — camada 3, rápida —
  ou só demorou — camada 1, fallback —, administradores notificados se passar de um limite maior —
  camada 2, sem reatribuição automática). 5 achados reais de produção corrigidos no primeiro dia e
  meio: mensagem falhando fora da janela de 24h do WhatsApp, 2 avisos seguidos pro cliente no mesmo
  ciclo, notificação chegando como "Sem conteúdo", alertas disparando fora do horário de
  atendimento, e uma janela de corrida no lote do job — detalhes → `status.md`.
- **[[conversation-export-pdf]]** (`features/conversation-export-pdf/`) — **25/09/2026:** quem pode exportar passou a ser a Função Personalizada (permissão `conversation_export`), PR #105 — a política checava um papel `supervisor` que nunca existiu e dava 500 para agente em vez de 403. Antes disso, 3 PRs de correção (#85/#86/#87, 24/08/2026), todas mergeadas/deployadas/confirmadas: PDF saindo com páginas em branco em cascata e imagem cortada no meio, achado exportando a conversa real de um contato. Causa raiz de verdade era CSS de paginação de impressão (`page-break-inside: avoid` em blocos sem tamanho limitado), não o que eu suspeitei inicialmente (GIF/frame de vídeo — essa suspeita levou a um fix real e válido pra GIF de verdade, só não era a causa DESSE caso específico). **Pendência conhecida, não corrigida**: "Exportar todas" tem limite nativo de 20 conversas (achado por acaso na mesma investigação, adiado por decisão do usuário) — detalhes → `status.md`.
- **[[whatsapp-number-checker]]** (`features/whatsapp-number-checker/`) — implementado e **ligado** (13/08/2026). Serviço Node standalone (Baileys/WhatsApp Web protocol) pra verificar se um número tem WhatsApp sem depender de serviço pago de terceiro nem expor dados de cliente. Configuração em Settings → Integrações (card próprio, QR code ao vivo, conectar/desconectar de verdade). Ligado em 3 pontos consultivos: antes do disparo em massa, ao criar contato manualmente, ao iniciar conversa nova com número digitado. Testado ponta a ponta em dev com sessão real pareada. **25/09/2026 (PR #106): o resultado passou a aparecer na interface** — selo na ficha do contato (com botão de refazer), no formulário de criação, no chip do início de conversa e no cabeçalho da conversa, com revalidação ao vivo a cada 12h (composable `useWhatsappVerification`). **Verificador pareado e conectado em produção** (confirmado em 25/09/2026 no `/health` do container); a ressalva antiga de "não pareado" saiu de validade. Pendente: ambiguidade do 9º dígito (BR).
- **Função Personalizada "Gerenciar campanhas"** — PR #79 mergeada/deployada e confirmada em produção (07/08/2026, função "Agente Mobílli" já com `campaign_manage` marcado pra toda a equipe). Nova permissão `campaign_manage`: libera Campanhas (Live chat/SMS/WhatsApp) e o disparo em massa de WhatsApp pra agente sem ser admin — mesmo padrão de `contact_manage`/`report_manage`. Achado na pesquisa: `WhatsappBulkDispatchPolicy` é uma policy separada da `CampaignPolicy`, também sem hook de Função Personalizada — as duas entraram sob a mesma permissão. PR #80 (mergeada/deployada, confirmada visualmente) corrigiu efeito colateral: tabela de Funções Personalizadas estourava a tela com várias permissões marcadas. Iterações de UX no card/dialog de disparo em massa, todas mergeadas/deployadas/confirmadas: PRs #81/#82 (badge com data real de agendamento, ícone muda quando já concluído) e PR #83 (dialog de Detalhes de disparo agendado mostra a lista real de pendentes, não fica mais zerado) — detalhes em `.ai/fixes-log.md`.
- **[[conversation-reply-restricted]]** (`features/conversation-reply-restricted/`) — completo e estável. PRs #70–#75 mergeadas/deployadas/confirmadas (04-05/08/2026); PR #75 corrigiu a causa raiz de tudo (`Enterprise::ConversationPolicy#show?` bloqueava QUALQUER ação do agente com só `conversation_reply_restricted`, bug desde a #70, nunca antes exercitado — auditoria achou +6 lugares com o mesmo gap, todos corrigidos juntos). Detalhes → `.ai/features/conversation-reply-restricted/status.md`.
- **Bug não relacionado, achado no caminho:** notificação órfã (conversa excluída) derrubava `/notifications` com 500 pra qualquer conta — PR #74, mergeada/deployada. Detalhes → `.ai/fixes-log.md`.
- **Atribuição automática após handoff pro time** — resolvido (04/08/2026): flag `advanced_assignment` destravada + Política de Atribuição "Atribuição - WhatsApp Produção" criada e vinculada à inbox Whatsapp Mobilli Prod (round_robin + longest_waiting, confirmado no banco). Detalhes → `archive/2026-08-misc.md`.
- **BotFlow respondia por cima de agente humano** — PR #69 (04/08/2026): conversa que um agente começa manualmente (template + auto-atribuição) não tinha `bot_state`, então a primeira resposta do cliente caía no bot do zero. Corrigido com guard `assignee_id.present?` em `BridgeService`. Detalhes → `.ai/features/bot-flow/status.md`.
- **Migração do número WhatsApp da Octadesk** — +55 27 99775-6598 migrado com sucesso pra conta própria "Mobílli Rentals Produção" (WABA `1854862678487143`, Phone Number ID `1236198529578372`), inbox nova no Chatwoot recebendo e enviando. Pendências: atribuir agentes/automação/SLA na inbox nova (não migra sozinho); limpar a conta antiga (que ficava com a Octa). Causa raiz e armadilhas → `archive/2026-08-misc.md`.
- **Upgrade Chatwoot** — **v4.18.0 em produção desde 29/09/2026 (PR #108)**. Três releases de uma
  vez (v4.17.0, v4.17.1, v4.18.0): 324 commits, 23 migrations e a subida para **Rails 7.2.3.1**. 35
  conflitos resolvidos; as decisões estão no corpo do PR e no commit do merge. O que vale lembrar:
  nosso `resolve_reply_source_id` foi **aposentado** (o upstream criou `InReplyToMessageFinder`, que
  faz o mesmo e trata empate ambíguo); o desvio do **Azure na transcrição mudou de casa** para
  `Llm::SpeechToTextService`, que é onde o client nasce agora — o upstream continua sem tratar Azure;
  nossa correção do **fim da lista filtrada** continua necessária (eles ainda esperam página vazia);
  **disparo em massa e o analytics nativo de campanhas convivem** na mesma tela. Verificado em
  produção depois do deploy: áudio com transcrição, imagem servida pela gem nova (`azure-blob`),
  lista de conversas e WhatsApp recebendo. **Dois sustos do deploy** (ver [[project_deploy_migrations]]):
  as 22 migrations ficaram pendentes por horas (o comando foi rodado no diretório local por engano, o
  que migra o banco de desenvolvimento e parece sucesso) e as quatro configurações de marca voltaram
  sozinhas ao padrão do Chatwoot na madrugada. **Gatilho identificado em 01/10/2026: não era o
  deploy, era o relógio** — o `Internal::ReconcilePlanConfigService`, agora pelo lado da marca.
  Corrigido no PR #113; detalhes em [[premium-unlock]].
- **Upgrade anterior** — v4.16.2 (PR #66, 03/08/2026), verificado e saudável (`needs_migration?` false, sem erro nos logs). **Medido em 28/09/2026:** o upstream já está na **v4.18.0** (18/09/2026; v4.17.0 e v4.17.1 no meio). Distância real: **374 commits** deles que não temos, **284** nossos que eles não têm, **33 migrations** novas e **105 arquivos** que os dois lados mexeram (os candidatos a conflito). Não é merge de tarde de sexta: pede branch própria, resolução em blocos, migrations ensaiadas num dump e revisão do que é nosso e frágil (BotFlow, Captain, verificador, exportação, pesquisa na conversa, tela de login). v4.16.1 (PR #65) também já em produção. Detalhes/achados → `archive/2026-07-misc.md` + `.ai/features/captain/status.md` (roteamento de modelo).
- **[[whatsapp-bulk-dispatch]]** (`features/whatsapp-bulk-dispatch/`) — completo, 9 PRs mescladas (#56–#64). PR #64 (backfill de contexto na primeira resposta) reverificado sem regressão após o upgrade v4.16.1.
- **[[captain-motofacil-access]]** (`features/captain-motofacil-access/`) — **EM ANDAMENTO, só local** (branch `feat/captain-motofacil-access`, 10/09/2026). Decisão do usuário: sair do menu do BotFlow para Captain 100% IA. Caso 1 = cliente sem acesso ao Moto Fácil: ferramentas `motofacil_lookup` (busca pelo telefone verificado da conversa) e `motofacil_generate_access` (senha 1x por conversa, enviada direto ao cliente e oculta da IA), transferência via `assign_team` pro `suporte app`. Caso 2 = negociação/vencimento/parcelamento (só dado: explica que não há negociação nem exceção; contestação/promoção → `financeiro`). Ferramenta nova `close_conversation` (encerra depois da despedida sem ligar o auto-resolve do Captain; com trava no servidor: não encerra se o cliente acabou de perguntar algo ou se o bot não perguntou "algo mais?"). Caso 3 = endereços das lojas/oficina (horário das lojas lido da inbox via `business_hours_check`; oficina é exceção). Caso 4 = vendas vão pro WhatsApp (92) 2398-1266 (filial Manaus). Caso 5 = pagamento/parcelas/recibo só na plataforma (link direto); "falta parcela / paga em aberto" exige parcelas + print do app (comprovante opcional) via ferramenta `installment_dispute_transfer` → `suporte app`. Correção no `AgentRunnerService`: respostas estruturadas múltiplas são publicadas juntas (a 1ª versão da correção descartava a resposta real). Resposta de pagamento **genérica** (decisão do usuário em 11/09/2026, a UI da plataforma pode mudar): só "é na plataforma (link), na parte de cobranças, e lá tem a opção de recibo" — sem abas, botões nem passo a passo. Roteamento pagamento × negociação corrigido no mesmo dia (o orquestrador respondia sozinho por causa da guardrail com a resposta pronta; a contestação caía no pagamento): 7 de 7 simulações certas; armadilhas do Captain v2 registradas no `status.md`. **Casos 7 e 8 (11/09/2026, a partir da análise das conversas de produção 5925, 7680 e 7661):** Caso 7 = moto com defeito, parada ou socorro. O bot nunca fala de bloqueio (risco jurídico) e diz que o diagnóstico é da manutenção. Moto parada → oferece socorro pela ferramenta nova `roadside_assistance_transfer`, que só transfere depois de o cliente mandar a localização e copia essa localização real na nota (a IA tinha inventado um endereço). Se recusar o socorro, é orientado a levar à oficina; moto rodando → agendamento com a `manutenção`; oficina de confiança do cliente é permitida. Caso 8 = multas: cobrança como qualquer outra, sem alteração; multa que não aparece no app → `suporte app`; dúvida detalhada → `documentação e multas`. Guardrail novo: nunca oferecer nem mencionar cartão ou facilidade de pagamento. Patches: o Captain passou a ler o pin de localização do WhatsApp, e respostas quase iguais na mesma rodada são descartadas (a pergunta saía repetida). Em aberto por decisão do usuário: ouvidoria e os alertas de conversa sem resposta. **Fallback quando a IA cai (11/09/2026, decisão do usuário):** sem menu como atendimento principal — o agente conduz tudo. Quando a IA falha, o job do Captain tenta de novo por ~40 s. Na falha final, a IA fica marcada como indisponível por 5 min (Redis) e a conversa segue o fallback: nova → menu do BotFlow (roda por dentro, assinado pelo assistente, só como reserva); em andamento → atendente com nota; fora do horário → atendente com aviso de horário. A varredura `Captain::UnansweredConversationsFallbackJob` (a cada 2 min) pega quem ficou sem resposta. Na troca em produção, remover o `AgentBotInbox` da inbox 5. Detalhes no `status.md` da feature. **Placa e CPF antes de transferir (11/09/2026, regra do usuário):** toda transferência para humano feita pela IA exige a placa e o CPF enviados pelo cliente (trava na `AssignTeamTool`, com o CPF validado pelos dígitos verificadores). Sem o dado, o bot insiste uma vez e transfere com "não informado". O socorro pede os dois junto com a localização. Com a IA fora do ar, não se exige. Oficina: sábado só para casos pendentes, sem agendamento (confirmado). Caminhos simulados com IA real; pendência menor: uma despedida sem encerrar na 1ª tentativa. Confirmado pelo usuário: agendamento em dia de semana → manutenção; nova locação depois de terminar a atual → WhatsApp de vendas. Caso 6 = troca de moto (exige motivo detalhado → pós-venda) e renovação (não existe; 1 locação por CPF). **11/09/2026:** troca de moto com motivo obrigatório (`motorcycle_swap_transfer`, aceita motivo dado por áudio via transcrição) e próximo horário de abertura calculado no servidor — feitos e simulados; transcrição de áudio ligada na conta local. "Algo mais?" logo depois de transferir: cortado no servidor (`HandoffReplyTrimmer`, só quando houve transferência na rodada), simulado. Como retomar na seção "Onde parei" do `status.md`; scripts em `features/captain-motofacil-access/scripts/`. Pausado em 15/09/2026 no commit WIP local `b1f99c1f2` (sem push), nada em produção; pendências de produção no `status.md`.
- **[[captain]]** (`features/captain/`) — em STANDBY. Bot ativo é o [[bot-flow]]. **🔴 Base de conhecimento apagada (achado 10/09/2026): 0 cenários e 0 FAQs em produção (eram 9 e 22), sem backup. Não dá pra só religar, ver `status.md`.** Pendências conhecidas: (1) cenário "Falar com Atendente" às vezes chuta time sem perguntar o assunto; (2) prompt reconciliado com o fluxo consent-first do upstream no upgrade v4.16.1, ainda sem validação humana de tom em português; (3) **migrado pra Azure OpenAI em 04/09/2026** (recurso `ai-mobilli-prod-eus2`, eastus2) — resolveu o problema de crédito da conta OpenAI antiga; sentimento, copilot e embeddings validados em produção. Transcrição de áudio também resolvida (PR #98) — o Azure só serve transcrição na rota clássica de deployment, então o serviço monta um client próprio; confirmado em produção às 19:07 UTC. Backlog reprocessado no mesmo dia (1080 de 1086 áudios transcritos) e o recurso antigo em eastus removido — ver `status.md`.
- **[[bot-flow]]** (`features/bot-flow/`) — bot de triagem ativo em produção desde 14/07/2026. PR #76 mergeada/deployada/confirmada (04/08/2026): conversa iniciada por agente via template ficava presa em `pending` pra sempre (achado investigando conversas do time financeiro) — mesma raiz da PR #69, corrigido no mesmo guard. **01/09/2026 (PRs #93/#94/#95, mergeadas/deployadas/confirmadas em produção)**: suporte à migração da plataforma de cobranças pro Moto Fácil — atalho por palavra-chave (bate com o botão "Solicite pelo WhatsApp" do painel antigo) + pergunta de triagem própria na saudação (novo estado `triagem_inicial`, WhatsApp limita a 3 botões/msg então não dava pra só somar ao menu principal), ambos transferindo pro time novo `suporte app`(8). Gotcha achado no caminho (documentado em `status.md`): toque em botão de resposta rápida volta pro bot com o **título visível**, não o `value` interno configurado — nunca tinha aparecido antes porque os botões anteriores sempre tiveram title/value parecidos o bastante pra funcionar por acidente. **02/10/2026 (PR #116, em produção):** o handoff entregava o time mas ninguém era atribuído, mesmo com agente online — o bot continuava como responsável (`ai_assignee`) e o Chatwoot não procura agente quando já há um. Vinha desde 06/08 sem ninguém notar; as **13 conversas antigas que ficaram paradas** (o deploy não as corrige) estavam todas no alvo da limpeza de 05/10/2026 e foram encerradas junto. Conferido no mesmo dia: nenhuma conversa ativa tem time ou agente com o bot ainda preso em `ai_assignee` — as 64 que ainda têm o campo são bot em triagem, que é o esperado. Primeiro spec do BotFlow nasceu aqui — detalhes e as duas armadilhas do cenário de teste → `status.md`.

## Concluído e estável (não iterado recentemente)

- **[[trash]]** (`features/trash/`) — Lixeira / Soft Delete.
- **[[audit-logs]]** (`features/audit-logs/`) — Logs de Auditoria.
- **[[premium-unlock]]** (`features/premium-unlock/`) — Destrave de features Enterprise.
- Histórico menor (Instance Status, upgrades v4.15.1/v4.16.1, round-robin) → `archive/2026-07-misc.md`.
- Histórico de agosto/2026 (migração WhatsApp Octadesk, upgrade v4.16.2) → `archive/2026-08-misc.md`.

## 🪦 Projetos descontinuados

- **Assistente IA Mobílli** — congelado, nunca foi pra produção. Vive em `git stash@{0}` (`mobilli-assistant-wip`). Ver `.ai/context.md`.
- **Typebot** — removido por completo, substituído pelo BotFlow.

## ✅ Pendência de segurança antiga — já resolvida (verificado 07/08/2026)

O vazamento de `provider_config` (API key da Meta, webhook token) via `GET /campaigns` mencionado aqui antes **já está corrigido**: `app/views/api/v1/models/_inbox.json.jbuilder:136` tem `json.provider_config ... if Current.account_user&.administrator?` — como a checagem é centralizada dentro do partial (não duplicada em cada controller que o usa), todo consumidor herda a proteção automaticamente. Reconfirmado ao implementar a permissão `campaign_manage` (PR #79): a checagem é por **role** (`administrator?`), não por permissão de Função Personalizada, então um agente com "Gerenciar campanhas" não vê `provider_config` mesmo tendo acesso a `GET /campaigns`.
