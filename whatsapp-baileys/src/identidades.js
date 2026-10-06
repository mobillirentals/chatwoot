const fs = require('fs');
const path = require('path');
const { jidNormalizedUser, isLidUser } = require('@whiskeysockets/baileys');
const pino = require('pino');

const logger = pino({ level: process.env.LOG_LEVEL || 'warn' });

// O WhatsApp esta trocando o identificador do contato por LID ('<id>@lid'), que NAO contem o
// telefone. Nas mensagens que o cliente manda, o Baileys 6.7 entrega o numero ao lado, em
// `senderPn` -- mas nas mensagens que SAIEM daqui (e nos recibos de entrega delas) a chave so tem
// o LID. E a versao instalada nao expoe tradutor de LID para numero.
//
// Entao a ponte guarda o que descobre, por dois caminhos que se complementam:
//   LID -> numero        aprendido quando o cliente escreve (LID e senderPn vem juntos)
//   id da msg -> numero  gravado no envio, quando o numero veio no proprio pedido
//
// O que se aprende vai para disco, junto da sessao. Na primeira versao isso vivia so em memoria e
// eu tratei a perda no restart como aceitavel -- nao e: o primeiro eco testado depois de um
// rebuild foi descartado por LID desconhecido. Deploy reinicia.
//
// Uma instancia por sessao: numeros diferentes conversam com contatos diferentes, e misturar os
// mapas faria uma sessao responder com o numero aprendido pela outra.

const LIMITE = 5000; // Map mantem ordem de insercao, entao o mais antigo sai primeiro
const ATRASO_PARA_GRAVAR = 2000; // agrupa rajada de mensagens numa escrita so

function criarIdentidades(pasta) {
  const arquivo = path.join(pasta, 'identidades.json');
  const porLid = new Map();
  const porMensagem = new Map();
  let gravacaoAgendada = null;

  function carregar() {
    try {
      const dados = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
      for (const [k, v] of dados.porLid || []) porLid.set(k, v);
      for (const [k, v] of dados.porMensagem || []) porMensagem.set(k, v);
      logger.info({ pasta, lids: porLid.size, mensagens: porMensagem.size }, 'identidades recuperadas do disco');
    } catch (err) {
      if (err.code !== 'ENOENT') logger.warn({ err: err.message, pasta }, 'nao consegui ler as identidades salvas, comecando do zero');
    }
  }

  function agendarGravacao() {
    if (gravacaoAgendada) return;
    gravacaoAgendada = setTimeout(() => {
      gravacaoAgendada = null;
      try {
        fs.mkdirSync(pasta, { recursive: true });
        // Escrita em temporario e rename: um restart no meio da escrita deixaria o JSON pela
        // metade, e a proxima leitura perderia TUDO em vez de so o ultimo aprendizado.
        const temporario = `${arquivo}.tmp`;
        fs.writeFileSync(temporario, JSON.stringify({ porLid: [...porLid], porMensagem: [...porMensagem] }));
        fs.renameSync(temporario, arquivo);
      } catch (err) {
        logger.warn({ err: err.message, pasta }, 'falha ao salvar as identidades');
      }
    }, ATRASO_PARA_GRAVAR);
    gravacaoAgendada.unref?.(); // nao segura o processo no encerramento
  }

  function guardar(mapa, chave, valor) {
    if (!chave || !valor) return;
    if (mapa.get(chave) === valor) return;
    if (mapa.size >= LIMITE) mapa.delete(mapa.keys().next().value);
    mapa.set(chave, valor);
    agendarGravacao();
  }

  function normalizar(jid) {
    if (!jid) return null;
    try {
      return jidNormalizedUser(jid); // tira o sufixo de dispositivo (':90')
    } catch {
      return jid;
    }
  }

  carregar();

  return {
    lembrarDoLid(jid, numero) {
      const chave = normalizar(jid);
      if (chave && isLidUser(chave)) guardar(porLid, chave, numero);
    },

    lembrarDaMensagem(id, numero) {
      guardar(porMensagem, id, numero);
    },

    // Ordem: o que esta na propria chave, depois o que aprendemos. `remoteJid` so serve quando e
    // numero de verdade -- um LID ali e identificador, nao telefone.
    resolverNumero(key) {
      if (!key) return null;

      const jid = normalizar(key.remoteJid);
      if (jid && !isLidUser(jid) && jid.endsWith('@s.whatsapp.net')) return jid.split('@')[0];

      const daChave = key.senderPn || key.participantPn || key.remoteJidAlt;
      if (daChave) return String(daChave).split('@')[0].split(':')[0];

      const porId = porMensagem.get(key.id);
      if (porId) return porId;

      return porLid.get(jid) || null;
    },
  };
}

module.exports = { criarIdentidades };
