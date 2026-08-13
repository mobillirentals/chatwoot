const express = require('express');
const QRCode = require('qrcode');
const { connect, getStatus, getLatestQr, getConnectedNumber, checkNumbers, logout } = require('./whatsappClient');

const PORT = process.env.PORT || 3300;
const API_TOKEN = process.env.CHECKER_API_TOKEN;
const MAX_BATCH_SIZE = 50;

const app = express();
app.use(express.json());

// Sem CHECKER_API_TOKEN configurado, o endpoint fica aberto — aceitavel pro uso local/manual
// de agora, mas exigir token assim que isso for exposto pra qualquer coisa alem do seu proprio
// terminal (inclusive uma futura integracao com o Rails).
function requireToken(req, res, next) {
  if (!API_TOKEN) return next();

  const provided = req.get('x-checker-token');
  if (provided !== API_TOKEN) {
    return res.status(401).json({ error: 'token invalido ou ausente (header X-Checker-Token)' });
  }
  next();
}

app.get('/health', (_req, res) => {
  const connection = getStatus();
  res.json({
    status: 'ok',
    whatsapp_connection: connection,
    whatsapp_number: connection === 'connected' ? getConnectedNumber() : null,
  });
});

app.post('/logout', requireToken, async (_req, res) => {
  try {
    await logout();
    res.json({ status: 'ok', whatsapp_connection: getStatus() });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Falha ao desconectar a sessao.' });
  }
});

app.get('/qr', async (_req, res) => {
  const status = getStatus();

  if (status === 'connected') {
    return res.json({ status, message: 'Sessao ja pareada, nenhum QR necessario.' });
  }

  const qr = getLatestQr();
  if (!qr) {
    return res.status(202).json({ status, message: 'Aguardando geracao do QR code, tente novamente em instantes.' });
  }

  const buffer = await QRCode.toBuffer(qr, { width: 400 });
  res.setHeader('Content-Type', 'image/png');
  res.send(buffer);
});

app.post('/check', requireToken, async (req, res) => {
  const { numbers } = req.body || {};

  if (!Array.isArray(numbers) || numbers.length === 0) {
    return res.status(400).json({ error: '"numbers" precisa ser uma lista nao vazia de telefones.' });
  }
  if (numbers.length > MAX_BATCH_SIZE) {
    return res.status(400).json({ error: `Maximo de ${MAX_BATCH_SIZE} numeros por requisicao.` });
  }

  try {
    const results = await checkNumbers(numbers);
    res.json({ checked_at: new Date().toISOString(), results });
  } catch (err) {
    if (err.code === 'NOT_CONNECTED') {
      return res.status(503).json({ error: err.message });
    }
    console.error(err);
    res.status(500).json({ error: 'Falha ao verificar numeros.' });
  }
});

app.listen(PORT, () => {
  console.log(`whatsapp-number-checker ouvindo na porta ${PORT}`);
});

connect().catch((err) => {
  console.error('Falha ao iniciar sessao do WhatsApp:', err);
});
