const http   = require('http');
const flows  = require('./flows');
const teams  = require('./teams');

const PORT      = Number(process.env.PORT || 3001);
const BOT_TOKEN = process.env.BOT_TOKEN;

if (!BOT_TOKEN) {
  console.error('[bot] BOT_TOKEN não definido. Configure a variável de ambiente.');
  process.exit(1);
}

// Carrega times do Chatwoot e aguarda antes de começar a atender
teams.load().then(() => {
  const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok' }));
      return;
    }

    if (req.method !== 'POST' || req.url !== '/webhook') {
      res.writeHead(404);
      res.end();
      return;
    }

    let raw = '';
    req.on('data', chunk => { raw += chunk; });
    req.on('end', () => {
      // Responde 200 imediatamente para o Chatwoot não reenfileirar o evento
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ received: true }));

      let payload;
      try {
        payload = JSON.parse(raw || '{}');
      } catch {
        return;
      }

      // Só processa mensagens recebidas do cliente em conversas pendentes
      if (payload.event !== 'message_created') return;
      if (payload.message_type !== 'incoming')  return;
      if (payload.private)                       return;
      if (payload.conversation?.status !== 'pending') return;

      flows.handle(payload).catch(err => {
        console.error('[bot] erro ao processar evento:', err.message);
      });
    });
  });

  server.listen(PORT, () => {
    const base = (process.env.CHATWOOT_BASE_URL || 'http://rails:3000').replace(/\/$/, '');
    console.log(`[bot] ouvindo na porta ${PORT}, Chatwoot em ${base}`);
  });
});
