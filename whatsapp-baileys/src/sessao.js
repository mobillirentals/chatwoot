const fs = require('fs/promises');
const path = require('path');
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion } = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const pino = require('pino');
const { criarIdentidades } = require('./identidades');

const logger = pino({ level: process.env.LOG_LEVEL || 'warn' });

// Uma sessao = um numero de WhatsApp = uma pasta de credenciais. Duas conexoes sobre a MESMA
// credencial se derrubam em loop, entao cada numero tem a sua -- e e por isso que acrescentar
// caixa nao e so subir outro container: a ponte precisa saber conviver com varias.
class Sessao {
  constructor(id, { raizDeAuth, aoReceber, aoEcoar, aoMudarStatus }) {
    this.id = id;
    this.pasta = path.join(raizDeAuth, id);
    this.sock = null;
    this.status = 'disconnected'; // disconnected | connecting | waiting_qr | connected
    this.qr = null;
    this.identidades = criarIdentidades(this.pasta);
    this.aoReceber = aoReceber;
    this.aoEcoar = aoEcoar;
    this.aoMudarStatus = aoMudarStatus;
    // Guarda a chave inteira das mensagens do cliente: marcar como lida no WhatsApp exige a chave,
    // nao basta o id. Sem isso nao da para devolver o visto-azul ao cliente.
    this.chavesRecebidas = new Map();
    // E guarda a mensagem inteira por id, porque citar uma mensagem no Baileys exige {key, message},
    // nao so o id. E o que faz a resposta citada do painel chegar citada no WhatsApp.
    this.mensagensPorId = new Map();
  }

  async conectar() {
    await fs.mkdir(this.pasta, { recursive: true });
    const { state, saveCreds } = await useMultiFileAuthState(this.pasta);
    const { version } = await fetchLatestBaileysVersion();

    this.sock = makeWASocket({
      version,
      auth: state,
      logger,
      printQRInTerminal: false, // QR exposto via HTTP (mais confiavel que ASCII em log de container)
      markOnlineOnConnect: true,
    });

    this.status = 'connecting';
    this.sock.ev.on('creds.update', saveCreds);
    this.sock.ev.on('connection.update', (u) => this.aoAtualizarConexao(u));
    this.sock.ev.on('messages.upsert', (e) => this.aoChegarMensagens(e));
    this.sock.ev.on('messages.update', (u) => this.aoAtualizarMensagens(u));

    return this;
  }

  aoAtualizarConexao(update) {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      this.qr = qr;
      this.status = 'waiting_qr';
      logger.warn({ sessao: this.id }, 'novo QR gerado');
    }

    if (connection === 'open') {
      this.status = 'connected';
      this.qr = null;
      logger.info({ sessao: this.id, numero: this.numero() }, 'sessao conectada');
    }

    if (connection === 'close') {
      this.status = 'disconnected';
      const statusCode = new Boom(lastDisconnect?.error)?.output?.statusCode;

      if (statusCode === DisconnectReason.loggedOut) {
        logger.error({ sessao: this.id }, 'desconectada via logout — e preciso parear de novo');
        return;
      }

      // Queda de rede, restart do WhatsApp etc. sao reconectaveis sem perder o pareamento:
      // as credenciais salvas continuam valendo.
      logger.warn({ sessao: this.id, statusCode }, 'conexao encerrada, reconectando...');
      this.conectar().catch((err) => logger.error({ err, sessao: this.id }, 'falha ao reconectar'));
    }
  }

  async aoChegarMensagens({ messages, type }) {
    logger.info({ sessao: this.id, type, qtd: messages?.length || 0 }, 'messages.upsert recebido');

    // 'append' e o historico que o aparelho despeja ao conectar — importar isso encheria o
    // Chatwoot de conversa velha.
    if (type !== 'notify') return;

    for (const msg of messages) {
      if (msg.key?.fromMe) {
        await this.repassarEco(msg);
        continue;
      }

      if (ehGrupoOuTransmissao(msg.key?.remoteJid)) {
        logger.info({ sessao: this.id, jid: msg.key?.remoteJid }, 'descartado: grupo, transmissao ou status');
        continue;
      }

      const numero = this.identidades.resolverNumero(msg.key);
      if (!numero) {
        logger.warn({ sessao: this.id, key: msg.key }, 'descartado: nao resolvi o numero do remetente');
        continue;
      }

      // Aqui o LID e o numero vem juntos — e a unica hora em que da para aprender a associacao
      // de que os recibos, os ecos e o visto-azul vao precisar depois.
      this.identidades.lembrarDoLid(msg.key.remoteJid, numero);
      this.guardarChave(numero, msg.key);
      this.guardarMensagem(msg);

      const texto = extrairTexto(msg);
      if (!texto) {
        logger.info({ sessao: this.id, id: msg.key?.id, tipos: Object.keys(msg.message || {}) },
          'descartado: sem texto (midia entra na proxima rodada)');
        continue;
      }

      try {
        await this.aoReceber(this.id, {
          from: numero,
          id: msg.key.id,
          timestamp: String(msg.messageTimestamp || Math.floor(Date.now() / 1000)),
          name: msg.pushName || null,
          text: texto,
          citou: idDaMensagemCitada(msg),
        });
      } catch (err) {
        logger.error({ err, sessao: this.id }, 'falha ao entregar mensagem recebida');
      }
    }
  }

  // Mensagem que saiu do aparelho (atendente respondendo pelo celular, resposta automatica do
  // WhatsApp Business) nao e do cliente, mas precisa aparecer na conversa: sem ela o proximo
  // atendente nao ve o que ja foi dito.
  async repassarEco(msg) {
    const destino = this.identidades.resolverNumero(msg.key);
    if (!destino) {
      logger.warn({ sessao: this.id, key: msg.key }, 'eco descartado: nao resolvi o destinatario');
      return;
    }

    const texto = extrairTexto(msg);
    if (!texto) return;

    try {
      await this.aoEcoar(this.id, {
        to: destino,
        id: msg.key.id,
        timestamp: String(msg.messageTimestamp || Math.floor(Date.now() / 1000)),
        text: texto,
      });
    } catch (err) {
      logger.error({ err, sessao: this.id }, 'falha ao entregar eco');
    }
  }

  async aoAtualizarMensagens(updates) {
    for (const { key, update } of updates || []) {
      if (!key?.fromMe) continue; // so acompanhamos o caminho das NOSSAS mensagens

      const status = STATUS_DO_BAILEYS[update?.status];
      if (!status) continue;

      const destino = this.identidades.resolverNumero(key);
      if (!destino) {
        logger.warn({ sessao: this.id, key }, 'status descartado: nao resolvi o destinatario');
        continue;
      }

      try {
        await this.aoMudarStatus(this.id, { id: key.id, status, timestamp: String(Math.floor(Date.now() / 1000)), recipient: destino });
      } catch (err) {
        logger.error({ err, sessao: this.id }, 'falha ao entregar status');
      }
    }
  }

  guardarMensagem(msg) {
    if (!msg.key?.id) return;
    if (this.mensagensPorId.size >= 500) this.mensagensPorId.delete(this.mensagensPorId.keys().next().value);
    this.mensagensPorId.set(msg.key.id, { key: msg.key, message: msg.message });
  }

  guardarChave(numero, key) {
    const chaves = this.chavesRecebidas.get(numero) || [];
    chaves.push({ remoteJid: key.remoteJid, id: key.id, fromMe: false, participant: key.participant });
    // Um visto-azul cobre as anteriores, entao guardar as ultimas basta.
    this.chavesRecebidas.set(numero, chaves.slice(-50));
  }

  async enviarTexto(numero, texto, idCitado = null) {
    this.exigirConexao();

    // Citar exige a mensagem original guardada. Quando ela nao esta em maos (reinicio, mensagem
    // antiga), manda sem citacao em vez de falhar: o texto chegar sem a citacao e melhor do que
    // nao chegar.
    const citada = idCitado ? this.mensagensPorId.get(idCitado) : null;
    if (idCitado) {
      logger.info({ sessao: this.id, idCitado, achou: Boolean(citada), guardadas: this.mensagensPorId.size },
        'envio com citacao');
    }
    const opcoes = citada ? { quoted: citada } : {};

    const enviada = await this.sock.sendMessage(paraJid(numero), { text: texto }, opcoes);
    const id = enviada?.key?.id || null;

    // No envio o numero veio no pedido; no recibo que chega depois, a chave so tem o LID.
    // Guardar agora e o que permite casar os dois.
    if (id) {
      const digitos = String(numero).replace(/\D/g, '');
      this.identidades.lembrarDaMensagem(id, digitos);
      this.identidades.lembrarDoLid(enviada?.key?.remoteJid, digitos);
      // Tambem guardamos as nossas: o agente pode citar a propria mensagem anterior.
      this.guardarMensagem(enviada);
    }

    return id;
  }

  // Devolve o visto-azul ao cliente. O Baileys exige a chave inteira, nao o id — por isso
  // guardamos as chaves das mensagens recebidas.
  async marcarComoLida(numero) {
    this.exigirConexao();

    const chaves = this.chavesRecebidas.get(String(numero).replace(/\D/g, '')) || [];
    if (chaves.length === 0) return 0;

    await this.sock.readMessages(chaves);
    this.chavesRecebidas.delete(String(numero).replace(/\D/g, ''));
    return chaves.length;
  }

  // 'composing' aparece como "digitando..." no aparelho do cliente e EXPIRA sozinho em ~10s:
  // quem chama precisa renovar enquanto o agente escreve.
  async avisarPresenca(numero, estado) {
    this.exigirConexao();
    await this.sock.sendPresenceUpdate(estado, paraJid(numero));
  }

  exigirConexao() {
    if (this.status === 'connected') return;

    const err = new Error(`Sessao ${this.id} nao esta conectada (status ${this.status}).`);
    err.code = 'NOT_CONNECTED';
    throw err;
  }

  // sock.user.id vem como "<numero>:<device>@s.whatsapp.net" — so o numero interessa.
  numero() {
    const bruto = this.sock?.user?.id;
    if (!bruto) return null;
    return bruto.split('@')[0].split(':')[0];
  }

  async desconectar() {
    if (this.sock) {
      try {
        await this.sock.logout();
      } catch (err) {
        logger.warn({ err: err.message, sessao: this.id }, 'erro no logout — limpando localmente mesmo assim');
      }
    }

    this.qr = null;
    this.status = 'disconnected';
    await this.limparPasta();
    await this.conectar();
  }

  // So o CONTEUDO da pasta, nunca a pasta em si: em bind mount (Docker Desktop/Windows) a pasta
  // e o ponto de montagem, e remove-la de dentro do container falha com EBUSY.
  async limparPasta() {
    const itens = await fs.readdir(this.pasta).catch(() => []);
    await Promise.all(itens.map((item) => fs.rm(path.join(this.pasta, item), { recursive: true, force: true })));
  }

  resumo() {
    return {
      id: this.id,
      status: 'ok',
      whatsapp_connection: this.status,
      whatsapp_number: this.status === 'connected' ? this.numero() : null,
    };
  }
}

const STATUS_DO_BAILEYS = {
  0: 'failed', // ERROR
  2: 'sent', // SERVER_ACK
  3: 'delivered', // DELIVERY_ACK
  4: 'read', // READ
  5: 'read', // PLAYED (audio ouvido conta como lido)
};

// Descarte por lista do que NAO serve, nunca do que serve: a primeira versao exigia
// '@s.whatsapp.net' e barrou a primeira mensagem real de teste, que chegou como '@lid'.
function ehGrupoOuTransmissao(jid) {
  if (!jid) return true;
  return jid.endsWith('@g.us') || jid.endsWith('@broadcast') || jid === 'status@broadcast' || jid.endsWith('@newsletter');
}

// O texto aparece em lugares diferentes conforme o tipo: mensagem simples, mensagem com
// formatacao/resposta (extendedTextMessage) e toque em botao de lista/resposta rapida.
function extrairTexto(msg) {
  const m = msg.message || {};
  return (
    m.conversation ||
    m.extendedTextMessage?.text ||
    m.buttonsResponseMessage?.selectedDisplayText ||
    m.listResponseMessage?.title ||
    m.templateButtonReplyMessage?.selectedDisplayText ||
    null
  );
}

// Quando o cliente responde citando, o id da mensagem citada vem no contextInfo — em lugares
// diferentes conforme o tipo da mensagem.
function idDaMensagemCitada(msg) {
  const m = msg.message || {};
  const contexto = m.extendedTextMessage?.contextInfo || m.imageMessage?.contextInfo || m.videoMessage?.contextInfo;
  return contexto?.stanzaId || null;
}

// Aceita numero com ou sem '+', espacos, tracos, parenteses — normaliza pra so digitos
// (formato internacional completo com DDI, ex: 5527999990001) antes de montar o JID.
function paraJid(numero) {
  return `${String(numero).replace(/\D/g, '')}@s.whatsapp.net`;
}

module.exports = { Sessao, paraJid };
