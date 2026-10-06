const fs = require('fs/promises');
const path = require('path');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  downloadMediaMessage,
} = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const pino = require('pino');
const { criarIdentidades } = require('./identidades');

const logger = pino({ level: process.env.LOG_LEVEL || 'warn' });

// Uma sessao = um numero de WhatsApp = uma pasta de credenciais. Duas conexoes sobre a MESMA
// credencial se derrubam em loop, entao cada numero tem a sua -- e e por isso que acrescentar
// caixa nao e so subir outro container: a ponte precisa saber conviver com varias.
class Sessao {
  constructor(id, { raizDeAuth, aoReceber, aoEcoar, aoMudarStatus, numeroEsperado = null }) {
    this.id = id;
    // Numa sessao que ja tem caixa, so o numero dela pode parear: outro numero continuaria com o
    // historico e os contatos do antigo, mas enviando de outro lugar -- o cliente receberia
    // resposta de um numero que nunca contatou. A checagem e no instante da conexao porque o
    // pareamento acontece no WhatsApp, fora do nosso alcance.
    this.numeroEsperado = numeroEsperado;
    this.recusa = null;
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
      const pareado = this.numero();

      if (this.numeroEsperado && pareado !== this.numeroEsperado) {
        logger.error({ sessao: this.id, pareado, esperado: this.numeroEsperado },
          'numero errado pareado — desfazendo antes de qualquer mensagem trafegar');
        this.recusa = { pareado, esperado: this.numeroEsperado };
        this.status = 'numero_errado';
        this.desconectar().catch((err) => logger.error({ err, sessao: this.id }, 'falha ao desfazer o pareamento errado'));
        return;
      }

      this.status = 'connected';
      this.qr = null;
      this.recusa = null;
      logger.info({ sessao: this.id, numero: pareado }, 'sessao conectada');
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

      const midia = descreverMidia(msg);
      const texto = extrairTexto(msg);

      if (!texto && !midia) {
        logger.info({ sessao: this.id, id: msg.key?.id, tipos: Object.keys(msg.message || {}) },
          'descartado: sem texto nem midia que a gente trate');
        continue;
      }

      try {
        await this.aoReceber(this.numero(), {
          from: numero,
          id: msg.key.id,
          timestamp: String(msg.messageTimestamp || Math.floor(Date.now() / 1000)),
          name: msg.pushName || null,
          text: texto,
          citou: idDaMensagemCitada(msg),
          midia,
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
      await this.aoEcoar(this.numero(), {
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
        await this.aoMudarStatus(this.numero(), { id: key.id, status, timestamp: String(Math.floor(Date.now() / 1000)), recipient: destino });
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

  // O Chatwoot pede o arquivo quando vai anexar a mensagem (media_url do provider aponta pra ca).
  // Baixar sob demanda evita guardar binario: a mensagem ja esta em maos, e o WhatsApp serve o
  // conteudo a partir dela.
  async baixarMidia(idDaMensagem) {
    this.exigirConexao();

    const guardada = this.mensagensPorId.get(idDaMensagem);
    if (!guardada) {
      const err = new Error(`Mensagem ${idDaMensagem} nao esta em maos para baixar a midia.`);
      err.code = 'NOT_FOUND';
      throw err;
    }

    const buffer = await downloadMediaMessage(guardada, 'buffer', {}, { logger, reuploadRequest: this.sock.updateMediaMessage });
    return { buffer, ...descreverMidia(guardada) };
  }

  async enviarMidia(numero, { mediaUrl, mediaType, mimeType, filename, caption, idCitado }) {
    this.exigirConexao();

    const url = urlAlcancavel(mediaUrl);
    const resposta = await fetch(url);
    if (!resposta.ok) throw new Error(`nao consegui baixar o anexo (${resposta.status}) em ${url}`);

    const buffer = Buffer.from(await resposta.arrayBuffer());
    const citada = idCitado ? this.mensagensPorId.get(idCitado) : null;
    const opcoes = citada ? { quoted: citada } : {};

    const enviada = await this.sock.sendMessage(paraJid(numero), montarMidia({ mediaType, mimeType, filename, caption, buffer }), opcoes);
    const id = enviada?.key?.id || null;

    if (id) {
      const digitos = String(numero).replace(/\D/g, '');
      this.identidades.lembrarDaMensagem(id, digitos);
      this.identidades.lembrarDoLid(enviada?.key?.remoteJid, digitos);
      this.guardarMensagem(enviada);
    }

    return id;
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
  //
  // E nunca o identidades.json: ele guarda o mapa LID -> numero aprendido conversa a conversa, que
  // NAO e credencial e continua valendo depois de reparear o mesmo numero. Apaga-lo fazia o
  // "Reconectar" jogar fora tudo que a ponte sabia, e os ecos e recibos paravam de achar a
  // conversa ate cada cliente escrever de novo.
  async limparPasta() {
    const itens = await fs.readdir(this.pasta).catch(() => []);
    await Promise.all(
      itens
        .filter((item) => item !== 'identidades.json')
        .map((item) => fs.rm(path.join(this.pasta, item), { recursive: true, force: true }))
    );
  }

  resumo() {
    return {
      id: this.id,
      // o numero so existe depois do pareamento — e e dele que a caixa nasce
      status: 'ok',
      whatsapp_connection: this.status,
      whatsapp_number: this.status === 'connected' ? this.numero() : null,
      expected_number: this.numeroEsperado,
      // preenchido quando alguem pareia um numero diferente do da caixa
      wrong_number: this.recusa,
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

// A URL do anexo vem montada para o NAVEGADOR (em desenvolvimento, localhost:3000). De dentro do
// container, localhost e a propria ponte -- dai o ECONNREFUSED. Quando a URL e do Active Storage
// servido pelo proprio Rails, trocamos a origem pela que a ponte usa para falar com ele.
//
// Em producao com storage externo (Azure Blob, S3) a URL ja e publica e assinada, nao casa com
// este padrao e passa intacta.
function urlAlcancavel(bruta) {
  if (!bruta.includes('/rails/active_storage/')) return bruta;

  const chatwoot = (process.env.CHATWOOT_URL || 'http://rails:3000').replace(/\/$/, '');
  try {
    const original = new URL(bruta);
    return `${chatwoot}${original.pathname}${original.search}`;
  } catch {
    return bruta;
  }
}

// Cada tipo de midia mora numa chave diferente da mensagem, com nomes de campo proprios. Devolve
// o que o Chatwoot precisa para anexar: o tipo que ele entende, a legenda e o mime.
const MIDIAS = [
  ['imageMessage', 'image'],
  ['videoMessage', 'video'],
  ['audioMessage', 'audio'],
  ['documentMessage', 'document'],
  ['stickerMessage', 'sticker'],
  ['documentWithCaptionMessage', 'document'],
];

function descreverMidia(msg) {
  const m = msg.message || {};
  // documentWithCaptionMessage embrulha o documento de verdade mais um nivel
  const interno = m.documentWithCaptionMessage?.message || m;

  for (const [chave, tipo] of MIDIAS) {
    const conteudo = interno[chave] || m[chave];
    if (!conteudo) continue;

    return {
      type: tipo,
      caption: conteudo.caption || null,
      mime_type: conteudo.mimetype || null,
      filename: conteudo.fileName || null,
      // Audio gravado no proprio WhatsApp vem com ptt: e mensagem de voz, nao arquivo de audio
      voice: Boolean(conteudo.ptt),
    };
  }

  return null;
}

// Monta o que o Baileys espera para cada tipo. Documento exige nome de arquivo, senao chega como
// "arquivo" sem identificacao nenhuma no aparelho do cliente.
function montarMidia({ mediaType, mimeType, filename, caption, buffer }) {
  if (mediaType === 'image') return { image: buffer, caption: caption || undefined, mimetype: mimeType || undefined };
  if (mediaType === 'video') return { video: buffer, caption: caption || undefined, mimetype: mimeType || undefined };
  // ptt: true faz chegar como mensagem de voz (com a onda), nao como arquivo anexado
  if (mediaType === 'audio') return { audio: buffer, mimetype: mimeType || 'audio/ogg; codecs=opus', ptt: true };

  return {
    document: buffer,
    mimetype: mimeType || 'application/octet-stream',
    fileName: filename || 'arquivo',
    caption: caption || undefined,
  };
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

module.exports = { Sessao, paraJid, descreverMidia, montarMidia, urlAlcancavel };
