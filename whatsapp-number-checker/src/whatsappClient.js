const fs = require('fs/promises');
const path = require('path');
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion } = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const pino = require('pino');

const AUTH_DIR = process.env.AUTH_DIR || './auth_session';
const logger = pino({ level: process.env.LOG_LEVEL || 'warn' });

let sock = null;
let connectionStatus = 'disconnected'; // disconnected | connecting | waiting_qr | connected
let latestQr = null;

async function connect() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();

  sock = makeWASocket({
    version,
    auth: state,
    logger,
    printQRInTerminal: false, // QR exposto via GET /qr (mais confiavel que ASCII em log de container)
  });

  connectionStatus = 'connecting';
  sock.ev.on('creds.update', saveCreds);
  sock.ev.on('connection.update', handleConnectionUpdate);

  return sock;
}

function handleConnectionUpdate(update) {
  const { connection, lastDisconnect, qr } = update;

  if (qr) {
    latestQr = qr;
    connectionStatus = 'waiting_qr';
    logger.warn('Novo QR code gerado — acesse GET /qr para parear o numero.');
  }

  if (connection === 'open') {
    connectionStatus = 'connected';
    latestQr = null;
    logger.info('Sessao do WhatsApp conectada.');
  }

  if (connection === 'close') {
    connectionStatus = 'disconnected';
    const statusCode = new Boom(lastDisconnect?.error)?.output?.statusCode;
    const loggedOut = statusCode === DisconnectReason.loggedOut;

    if (loggedOut) {
      logger.error('Sessao desconectada via logout — apague auth_session/ e escaneie um novo QR.');
      return;
    }

    // Qualquer outro motivo (queda de rede, restart do WhatsApp, etc.) e reconectavel
    // sem perder o pareamento — as credenciais salvas em AUTH_DIR continuam validas.
    logger.warn(`Conexao encerrada (statusCode=${statusCode}), reconectando...`);
    connect().catch((err) => logger.error(err, 'falha ao reconectar'));
  }
}

function getStatus() {
  return connectionStatus;
}

function getLatestQr() {
  return latestQr;
}

// sock.user.id vem como "<numero>:<device>@s.whatsapp.net" — so o numero interessa pra exibicao.
function getConnectedNumber() {
  const rawId = sock?.user?.id;
  if (!rawId) return null;
  return rawId.split('@')[0].split(':')[0];
}

// Desloga de verdade no WhatsApp (nao so localmente) e limpa as credenciais salvas, depois
// reconecta imediatamente com estado zerado — assim um QR novo fica disponivel em GET /qr sem
// precisar reiniciar o container manualmente.
async function logout() {
  if (sock) {
    try {
      await sock.logout();
    } catch (err) {
      logger.warn(err, 'erro ao chamar logout no WhatsApp — prosseguindo com a limpeza local mesmo assim');
    }
  }

  latestQr = null;
  connectionStatus = 'disconnected';

  await clearAuthDir();
  await connect();
}

// So limpa o CONTEUDO de AUTH_DIR, nunca a pasta em si — em bind mount (Docker Desktop/
// Windows), a pasta e o proprio ponto de montagem, e um rm -rf nela falha com
// EBUSY: resource busy or locked (tentar remover o mountpoint de dentro do container).
async function clearAuthDir() {
  const entries = await fs.readdir(AUTH_DIR).catch(() => []);
  await Promise.all(
    entries.map((entry) => fs.rm(path.join(AUTH_DIR, entry), { recursive: true, force: true }))
  );
}

// Aceita numero com ou sem '+', espacos, tracos, parenteses — normaliza pra so digitos
// (formato internacional completo com DDI, ex: 5527999990001) antes de montar o JID.
function toJid(rawNumber) {
  const digits = String(rawNumber).replace(/\D/g, '');
  return `${digits}@s.whatsapp.net`;
}

async function checkNumbers(numbers) {
  if (connectionStatus !== 'connected') {
    const err = new Error('Sessao do WhatsApp ainda nao esta conectada (ver GET /qr).');
    err.code = 'NOT_CONNECTED';
    throw err;
  }

  const jids = numbers.map(toJid);
  const found = await sock.onWhatsApp(...jids);

  // onWhatsApp so retorna entradas pros numeros que EXISTEM (as vezes nem isso, dependendo
  // da versao) — nunca confiar no array bruto pra saber quem nao existe. Reconstroi a lista
  // completa a partir do input original, marcando exists:false pra tudo que nao veio de volta.
  const foundByJid = new Map(found.map((r) => [r.jid, r]));

  return numbers.map((input, i) => {
    const jid = jids[i];
    const match = foundByJid.get(jid);
    return { input, exists: Boolean(match?.exists), jid: match?.jid || null };
  });
}

module.exports = { connect, getStatus, getLatestQr, getConnectedNumber, checkNumbers, logout };
