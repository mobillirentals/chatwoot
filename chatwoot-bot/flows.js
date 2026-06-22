const api    = require('./api');
const { STATES, get: getState, set: setState } = require('./state');
const teams  = require('./teams');
const { isBusinessHours } = require('./business-hours');

// ─── Textos ───────────────────────────────────────────────────────────────────

const T = {
  fora_expediente:
    '⏰ Nosso horário de atendimento é:\n' +
    '*Segunda a Sexta:* 08h às 18h\n' +
    '*Sábados:* 08h às 12h\n\n' +
    'Sua mensagem foi registrada. Retornaremos no próximo dia útil.',

  encerrar_fora:
    'Agradecemos pela compreensão e até logo! 💪🧡🏍️',

  saudacao: nome =>
    `Olá, *${nome}*! 👋 Este é o canal de atendimento oficial da *Mobílli Rentals*.`,

  menu_principal:
    'Como podemos te ajudar? Escolha uma opção:\n\n' +
    '*1* - 💰 Financeiro\n' +
    '*2* - 🔧 Ajuda / Operações\n' +
    '*3* - 🆘 Socorro / Sinistro',

  menu_financeiro:
    'Ótimo! Qual seria o assunto?\n\n' +
    '*1* - Mensalidade\n' +
    '*2* - Multas e Franquias\n' +
    '*3* - Fornecedores\n' +
    '*0* - ⬅️ Voltar',

  menu_ajuda:
    '😀 Ótimo! Qual setor deseja contatar?\n\n' +
    '*1* - 🔧 Oficina\n' +
    '*2* - ❓ Dúvidas\n' +
    '*3* - 📣 Ouvidoria\n' +
    '*0* - ⬅️ Voltar',

  menu_oficina:
    'O que você precisa?\n\n' +
    '*1* - 📅 Marcar revisão (link online)\n' +
    '*2* - 👨‍🔧 Falar com a equipe de Manutenção\n' +
    '*0* - ⬅️ Voltar',

  menu_duvidas:
    'Sobre qual assunto você tem dúvidas?\n\n' +
    '*1* - 🚦 Multas de trânsito\n' +
    '*2* - 📋 Dúvidas contratuais\n' +
    '*3* - 📄 Documentos\n' +
    '*0* - ⬅️ Voltar',

  menu_ouvidoria:
    'O que deseja registrar?\n\n' +
    '*1* - 🔍 Denúncia\n' +
    '*2* - 😤 Reclamação\n' +
    '*3* - 💡 Sugestão\n' +
    '*0* - ⬅️ Voltar',

  menu_urgencias:
    'Qual o tipo de ocorrência?\n\n' +
    '*1* - 🆘 Socorro (emergência na estrada)\n' +
    '*2* - 🚗💥 Acidente\n' +
    '*3* - 🔒 Furto / Roubo\n' +
    '*0* - ⬅️ Voltar',

  link_revisao:
    '📅 Acesse o link abaixo para agendar sua revisão:\n' +
    'https://mobillirentals.com.br/reservasdaoficinamobilli\n\n' +
    'Em caso de dúvidas, estamos à disposição. Até logo! 👋',

  denuncia_ack:
    '🔍 Sua denúncia será analisada com total sigilo e seriedade. ' +
    'Em breve um responsável da Ouvidoria entrará em contato.',

  reclamacao_q1:
    '📝 Para registrar sua reclamação, preciso de algumas informações.\n\n' +
    '*Quando aconteceu?* (data/hora aproximada)',

  reclamacao_q2:
    '*Onde foi?* (endereço, unidade ou descrição do local)',

  reclamacao_fim:
    '✅ Reclamação registrada! Um atendente da Ouvidoria irá analisá-la em breve.',

  sinistro_aviso:
    '⚠️ *Atenção:* O acionamento indevido do serviço de guincho/remoção pode ' +
    'gerar custos ao contratante, conforme previsto em contrato.',

  sinistro_nome:     'Por favor, informe seu *nome completo*:',
  sinistro_placa:    'Qual é a *placa da motocicleta* envolvida?',
  sinistro_location: '📍 Envie sua *localização em tempo real* ou descreva o endereço:',
  sinistro_ref:      'Informe um *ponto de referência* próximo ao local:',

  sinistro_instrucoes:
    '🚨 *Instruções de emergência:*\n\n' +
    '• Ligue para nosso suporte: *(27) 99264-9884*\n' +
    '• Se necessário: PM *190* | SAMU *192*\n' +
    '• Providencie o *Boletim de Ocorrência (B.O.)*\n\n' +
    'Um atendente do setor de Sinistro já foi notificado e entrará em contato.',

  aguardar:
    '⏳ Aguarde um instante, estou transferindo você para um atendente...',

  invalida: menu =>
    `❓ Opção não reconhecida. Por favor, escolha uma das opções abaixo.\n\n${menu}`,
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function contactName(payload) {
  return (
    payload.sender?.name ||
    payload.conversation?.meta?.sender?.name ||
    'cliente'
  );
}

async function handoffToTeam(conversationId, teamName, label) {
  const teamId = teams.getIdByName(teamName);
  if (teamId) {
    await api.assignTeam(conversationId, teamId).catch(e =>
      console.warn(`[flows] assignTeam "${teamName}" falhou: ${e.message}`)
    );
  } else {
    console.warn(`[flows] time não encontrado: "${teamName}"`);
  }
  if (label) {
    await api.addLabel(conversationId, label).catch(() => {});
  }
  await api.handoff(conversationId);
  setState(conversationId, STATES.DONE);
}

async function closeConversation(conversationId) {
  await api.resolve(conversationId);
  setState(conversationId, STATES.DONE);
}

// ─── Handlers por estado ──────────────────────────────────────────────────────

async function onInitial(cid, payload) {
  const nome = contactName(payload);

  if (!isBusinessHours()) {
    await api.sendMessage(cid, T.fora_expediente);
    await api.sendMessage(cid, T.encerrar_fora);
    await closeConversation(cid);
    return;
  }

  await api.sendMessage(cid, T.saudacao(nome));
  await api.sendMessage(cid, T.menu_principal);
  setState(cid, STATES.MAIN_MENU);
}

async function onMainMenu(cid, text) {
  switch (text) {
    case '1':
      await api.sendMessage(cid, T.menu_financeiro);
      setState(cid, STATES.FINANCEIRO_MENU);
      break;
    case '2':
      await api.sendMessage(cid, T.menu_ajuda);
      setState(cid, STATES.AJUDA_MENU);
      break;
    case '3':
      await api.sendMessage(cid, T.menu_urgencias);
      setState(cid, STATES.URGENCIAS_MENU);
      break;
    default:
      await api.sendMessage(cid, T.invalida(T.menu_principal));
  }
}

async function onFinanceiro(cid, text) {
  switch (text) {
    case '1':
      await api.sendMessage(cid, T.aguardar);
      await handoffToTeam(cid, 'financeiro - contas a receber', 'mensalidade');
      break;
    case '2':
      await api.sendMessage(cid, T.aguardar);
      await handoffToTeam(cid, 'financeiro - contas a pagar', 'multas-franquias');
      break;
    case '3':
      await api.sendMessage(cid, T.aguardar);
      await handoffToTeam(cid, 'financeiro - contas a receber', 'fornecedores');
      break;
    case '0':
      await api.sendMessage(cid, T.menu_principal);
      setState(cid, STATES.MAIN_MENU);
      break;
    default:
      await api.sendMessage(cid, T.invalida(T.menu_financeiro));
  }
}

async function onAjuda(cid, text) {
  switch (text) {
    case '1':
      await api.sendMessage(cid, T.menu_oficina);
      setState(cid, STATES.OFICINA_MENU);
      break;
    case '2':
      await api.sendMessage(cid, T.menu_duvidas);
      setState(cid, STATES.DUVIDAS_MENU);
      break;
    case '3':
      await api.sendMessage(cid, T.menu_ouvidoria);
      setState(cid, STATES.OUVIDORIA_MENU);
      break;
    case '0':
      await api.sendMessage(cid, T.menu_principal);
      setState(cid, STATES.MAIN_MENU);
      break;
    default:
      await api.sendMessage(cid, T.invalida(T.menu_ajuda));
  }
}

async function onOficina(cid, text) {
  switch (text) {
    case '1':
      await api.sendMessage(cid, T.link_revisao);
      await closeConversation(cid);
      break;
    case '2':
      await api.sendMessage(cid, T.aguardar);
      await handoffToTeam(cid, 'manutenção', 'manutencao');
      break;
    case '0':
      await api.sendMessage(cid, T.menu_ajuda);
      setState(cid, STATES.AJUDA_MENU);
      break;
    default:
      await api.sendMessage(cid, T.invalida(T.menu_oficina));
  }
}

async function onDuvidas(cid, text) {
  switch (text) {
    case '1':
      await api.sendMessage(cid, T.aguardar);
      await handoffToTeam(cid, 'frota - multas e documentos', 'multas-transito');
      break;
    case '2':
      await api.sendMessage(cid, T.aguardar);
      await handoffToTeam(cid, 'pós-venda', 'duvidas-contratuais');
      break;
    case '3':
      await api.sendMessage(cid, T.aguardar);
      await handoffToTeam(cid, 'frota - multas e documentos', 'documentos');
      break;
    case '0':
      await api.sendMessage(cid, T.menu_ajuda);
      setState(cid, STATES.AJUDA_MENU);
      break;
    default:
      await api.sendMessage(cid, T.invalida(T.menu_duvidas));
  }
}

async function onOuvidoria(cid, text) {
  switch (text) {
    case '1':
      await api.sendMessage(cid, T.denuncia_ack);
      await handoffToTeam(cid, 'ouvidoria', 'denuncia');
      break;
    case '2':
      await api.sendMessage(cid, T.reclamacao_q1);
      setState(cid, STATES.OUVIDORIA_COLLECT, { step: 1 });
      break;
    case '3':
      await api.sendMessage(cid, T.aguardar);
      await handoffToTeam(cid, 'ouvidoria', 'sugestao');
      break;
    case '0':
      await api.sendMessage(cid, T.menu_ajuda);
      setState(cid, STATES.AJUDA_MENU);
      break;
    default:
      await api.sendMessage(cid, T.invalida(T.menu_ouvidoria));
  }
}

async function onOuvidoriaCollect(cid, text, data) {
  if (data.step === 1) {
    setState(cid, STATES.OUVIDORIA_COLLECT, { step: 2, quando: text });
    await api.sendMessage(cid, T.reclamacao_q2);
  } else {
    setState(cid, STATES.OUVIDORIA_COLLECT, { ...data, onde: text });
    await api.sendMessage(cid, T.reclamacao_fim);
    await handoffToTeam(cid, 'ouvidoria', 'reclamacao');
  }
}

async function onUrgencias(cid, text) {
  switch (text) {
    case '1':
      await api.sendMessage(cid, T.aguardar);
      await handoffToTeam(cid, 'socorro', 'socorro');
      break;
    case '2':
    case '3': {
      const tipo = text === '2' ? 'acidente' : 'furto-roubo';
      await api.sendMessage(cid, T.sinistro_aviso);
      await api.sendMessage(cid, T.sinistro_nome);
      setState(cid, STATES.SINISTRO_COLLECT_NAME, { tipo });
      break;
    }
    case '0':
      await api.sendMessage(cid, T.menu_principal);
      setState(cid, STATES.MAIN_MENU);
      break;
    default:
      await api.sendMessage(cid, T.invalida(T.menu_urgencias));
  }
}

async function onSinistroCollect(cid, text, currentState, data) {
  switch (currentState) {
    case STATES.SINISTRO_COLLECT_NAME:
      setState(cid, STATES.SINISTRO_COLLECT_PLATE, { nome: text });
      await api.sendMessage(cid, T.sinistro_placa);
      break;

    case STATES.SINISTRO_COLLECT_PLATE:
      setState(cid, STATES.SINISTRO_COLLECT_LOCATION, { placa: text });
      await api.sendMessage(cid, T.sinistro_location);
      break;

    case STATES.SINISTRO_COLLECT_LOCATION:
      setState(cid, STATES.SINISTRO_COLLECT_REFERENCE, { localizacao: text });
      await api.sendMessage(cid, T.sinistro_ref);
      break;

    case STATES.SINISTRO_COLLECT_REFERENCE:
      setState(cid, STATES.DONE, { referencia: text });
      await api.sendMessage(cid, T.sinistro_instrucoes);
      await handoffToTeam(cid, 'sinistro', data.tipo || 'sinistro');
      break;
  }
}

// ─── Dispatcher principal ─────────────────────────────────────────────────────

async function handle(payload) {
  const cid = payload.conversation?.id;
  if (!cid) return;

  const text    = String(payload.content || '').trim();
  const conv    = getState(cid);
  const current = conv?.state  || STATES.INITIAL;
  const data    = conv?.data   || {};

  if (current === STATES.DONE) return;

  switch (current) {
    case STATES.INITIAL:                  return onInitial(cid, payload);
    case STATES.MAIN_MENU:                return onMainMenu(cid, text);
    case STATES.FINANCEIRO_MENU:          return onFinanceiro(cid, text);
    case STATES.AJUDA_MENU:               return onAjuda(cid, text);
    case STATES.OFICINA_MENU:             return onOficina(cid, text);
    case STATES.DUVIDAS_MENU:             return onDuvidas(cid, text);
    case STATES.OUVIDORIA_MENU:           return onOuvidoria(cid, text);
    case STATES.OUVIDORIA_COLLECT:        return onOuvidoriaCollect(cid, text, data);
    case STATES.URGENCIAS_MENU:           return onUrgencias(cid, text);
    case STATES.SINISTRO_COLLECT_NAME:
    case STATES.SINISTRO_COLLECT_PLATE:
    case STATES.SINISTRO_COLLECT_LOCATION:
    case STATES.SINISTRO_COLLECT_REFERENCE:
      return onSinistroCollect(cid, text, current, data);
  }
}

module.exports = { handle };
