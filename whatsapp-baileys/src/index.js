const express = require('express');
const QRCode = require('qrcode');
const gerenciador = require('./gerenciador');
const { deliverIncomingMessage, deliverEcho, deliverStatus } = require('./chatwoot');

const PORT = process.env.PORT || 3400;
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN;

const app = express();
app.use(express.json());

// O token nao e opcional: esta ponte ENVIA mensagem em nome da empresa, entao um endpoint aberto
// deixaria qualquer um no alcance da rede mandar WhatsApp para qualquer numero. Sem BRIDGE_TOKEN
// o servico nem sobe.
function exigirToken(req, res, next) {
  if (req.get('x-bridge-token') !== BRIDGE_TOKEN) {
    return res.status(401).json({ error: 'token invalido ou ausente (header X-Bridge-Token)' });
  }
  next();
}

// Toda rota de sessao passa por aqui: 404 explicito e melhor que estourar em 'undefined'.
function comSessao(req, res, next) {
  const sessao = gerenciador.obter(req.params.id);
  if (!sessao) return res.status(404).json({ error: `sessao ${req.params.id} nao existe` });

  req.sessao = sessao;
  next();
}

function tratarErro(res, err) {
  if (err.code === 'NOT_CONNECTED') return res.status(503).json({ error: err.message });

  console.error(err);
  return res.status(500).json({ error: err.message || 'erro na ponte' });
}

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', sessoes: gerenciador.listar() });
});

app.get('/sessions', exigirToken, (_req, res) => {
  res.json({ sessoes: gerenciador.listar() });
});

// Cria (ou devolve) a sessao de um numero. E o primeiro passo da tela de conexao: cria, depois
// busca o QR, depois acompanha o status ate conectar.
app.post('/sessions', exigirToken, async (req, res) => {
  const { id } = req.body || {};
  if (!gerenciador.normalizarId(id)) {
    return res.status(400).json({ error: '"id" precisa ser o numero da caixa, com DDI' });
  }

  try {
    const sessao = await gerenciador.abrir(id);
    res.json(sessao.resumo());
  } catch (err) {
    tratarErro(res, err);
  }
});

app.get('/sessions/:id/health', comSessao, (req, res) => {
  res.json(req.sessao.resumo());
});

// Sem token de proposito: so devolve o QR de uma sessao ainda nao pareada, e o Rails faz proxy
// disso para a tela de conexao. Quem tem o QR consegue parear — por isso ele some assim que a
// sessao conecta.
app.get('/sessions/:id/qr', comSessao, async (req, res) => {
  const { status, qr } = req.sessao;

  if (status === 'connected') {
    return res.json({ status, message: 'Sessao ja pareada, nenhum QR necessario.' });
  }
  if (!qr) {
    return res.status(202).json({ status, message: 'Aguardando geracao do QR code, tente de novo em instantes.' });
  }

  if (req.query.format === 'text') return res.json({ status, qr });

  const buffer = await QRCode.toBuffer(qr, { width: 400 });
  res.setHeader('Content-Type', 'image/png');
  res.send(buffer);
});

app.post('/sessions/:id/send', exigirToken, comSessao, async (req, res) => {
  // quoted_id: id da mensagem que esta sendo respondida, quando o agente usa "responder" no painel
  const { to, text, quoted_id: quotedId } = req.body || {};
  if (!to || !text) return res.status(400).json({ error: '"to" e "text" sao obrigatorios.' });

  try {
    res.json({ status: 'ok', message_id: await req.sessao.enviarTexto(to, text, quotedId) });
  } catch (err) {
    tratarErro(res, err);
  }
});

// Devolve o visto-azul ao cliente quando o agente abre a conversa no painel.
app.post('/sessions/:id/read', exigirToken, comSessao, async (req, res) => {
  const { to } = req.body || {};
  if (!to) return res.status(400).json({ error: '"to" e obrigatorio.' });

  try {
    res.json({ status: 'ok', marcadas: await req.sessao.marcarComoLida(to) });
  } catch (err) {
    tratarErro(res, err);
  }
});

// "digitando..." no aparelho do cliente. Expira sozinho em ~10s, entao quem chama renova enquanto
// o agente escreve.
app.post('/sessions/:id/presence', exigirToken, comSessao, async (req, res) => {
  const { to, state } = req.body || {};
  const estados = ['composing', 'paused', 'available', 'unavailable', 'recording'];
  if (!to || !estados.includes(state)) {
    return res.status(400).json({ error: `"to" e obrigatorio e "state" deve ser um de: ${estados.join(', ')}` });
  }

  try {
    await req.sessao.avisarPresenca(to, state);
    res.json({ status: 'ok' });
  } catch (err) {
    tratarErro(res, err);
  }
});

app.post('/sessions/:id/logout', exigirToken, comSessao, async (req, res) => {
  try {
    await gerenciador.fechar(req.params.id);
    res.json({ status: 'ok', ...req.sessao.resumo() });
  } catch (err) {
    tratarErro(res, err);
  }
});

if (!BRIDGE_TOKEN) {
  console.error('BRIDGE_TOKEN e obrigatorio: a ponte envia mensagem em nome da empresa e nao pode ficar aberta.');
  process.exit(1);
}

gerenciador.definirGanchos({
  aoReceber: deliverIncomingMessage,
  aoEcoar: deliverEcho,
  aoMudarStatus: deliverStatus,
});

gerenciador
  .retomarSessoesSalvas()
  .catch((err) => console.error('falha ao retomar sessoes salvas', err))
  .finally(() => {
    app.listen(PORT, () => console.log(`ponte baileys ouvindo na porta ${PORT}`));
  });
