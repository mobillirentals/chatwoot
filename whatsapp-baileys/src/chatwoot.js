const pino = require('pino');

const logger = pino({ level: process.env.LOG_LEVEL || 'warn' });

const CHATWOOT_URL = (process.env.CHATWOOT_URL || 'http://rails:3000').replace(/\/$/, '');
const WEBHOOK_TOKEN = process.env.CHATWOOT_WEBHOOK_TOKEN || '';

// O Chatwoot aceita dois formatos no webhook de WhatsApp. O da Meta vem embrulhado em
// entry/changes e e localizado pelo metadata do payload; o outro, herdado do 360dialog, traz as
// chaves na raiz e usa o numero da URL para achar a caixa. Usamos o segundo: nao exige inventar
// phone_number_id nem fingir ser a Meta, e o provider 'baileys' do Rails ja roteia para o servico
// que le esse formato.
//
// Tres formatos de entrega, todos ja entendidos pelo servico base do Chatwoot:
//   messages       -> mensagem do cliente
//   message_echoes -> mensagem que saiu por fora do painel (atendente no celular)
//   statuses       -> recibo de entrega e leitura
//
// A caixa de destino vem do NUMERO pareado na sessao (o webhook do Chatwoot e por numero), nao do
// id dela — foi justamente separar os dois que permitiu parear sem digitar o numero antes.

function payloadDeRecebida({ from, id, timestamp, name, text, citou, midia }) {
  const mensagem = { from, id, timestamp, type: 'text', text: { body: text } };

  // Mídia: o Chatwoot le `messages[0][<tipo>]` e baixa pelo `id` usando o media_url do provider —
  // mesmo formato do 360dialog, entao nao ha nada a traduzir do lado do Rails.
  if (midia) {
    // Audio gravado no WhatsApp e mensagem de voz; o Chatwoot distingue os dois tipos.
    mensagem.type = midia.voice ? 'voice' : midia.type;
    delete mensagem.text;
    mensagem[mensagem.type] = {
      id,
      caption: midia.caption || undefined,
      mime_type: midia.mime_type || undefined,
      filename: midia.filename || undefined,
    };
    if (text) mensagem[mensagem.type].caption = text;
  }
  // `context.id` e exatamente o que o Chatwoot le para ligar a resposta a mensagem citada
  // (process_in_reply_to) — mesmo campo que a Meta manda.
  if (citou) mensagem.context = { id: citou };

  return {
    contacts: [{ wa_id: from, profile: { name: name || from } }],
    messages: [mensagem],
  };
}

// No eco os papeis se invertem: `from` e a empresa e `to` e o cliente -- e e do `to` que o
// Chatwoot tira o contato.
function payloadDeEco(numeroDaCaixa, { to, id, timestamp, text }) {
  return {
    contacts: [{ wa_id: to }],
    message_echoes: [{ from: numeroDaCaixa, to, id, timestamp, type: 'text', text: { body: text } }],
  };
}

function payloadDeStatus({ id, status, timestamp, recipient }) {
  return { statuses: [{ id, status, timestamp, recipient_id: recipient }] };
}

async function entregar(numeroDaCaixa, payload, descricao) {
  const url = `${CHATWOOT_URL}/webhooks/whatsapp/${encodeURIComponent(`+${numeroDaCaixa}`)}`;
  const resposta = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      // Sem assinatura da Meta para conferir, e este o segredo que prova que veio da ponte e nao
      // de alguem injetando conversa na caixa.
      'X-Bridge-Token': WEBHOOK_TOKEN,
    },
    body: JSON.stringify(payload),
  });

  if (!resposta.ok) {
    const corpo = await resposta.text().catch(() => '');
    throw new Error(`Chatwoot respondeu ${resposta.status}: ${corpo.slice(0, 200)}`);
  }

  logger.info({ ...descricao, caixa: numeroDaCaixa }, 'entregue ao Chatwoot');
}

module.exports = {
  deliverIncomingMessage: (sessaoId, msg) =>
    entregar(sessaoId, payloadDeRecebida(msg), { tipo: 'recebida', from: msg.from, id: msg.id }),

  deliverEcho: (sessaoId, msg) =>
    entregar(sessaoId, payloadDeEco(sessaoId, msg), { tipo: 'eco', to: msg.to, id: msg.id }),

  deliverStatus: (sessaoId, status) =>
    entregar(sessaoId, payloadDeStatus(status), { tipo: 'status', status: status.status, id: status.id }),

  payloadDeRecebida,
  payloadDeEco,
  payloadDeStatus,
};
