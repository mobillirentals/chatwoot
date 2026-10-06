const fs = require('fs/promises');
const { randomUUID } = require('crypto');
const pino = require('pino');
const { Sessao } = require('./sessao');

const logger = pino({ level: process.env.LOG_LEVEL || 'warn' });

const RAIZ_DE_AUTH = process.env.AUTH_DIR || './auth_session';

const sessoes = new Map();
let ganchos = { aoReceber: async () => {}, aoEcoar: async () => {}, aoMudarStatus: async () => {} };

function definirGanchos(novos) {
  ganchos = { ...ganchos, ...novos };
}

// O id da sessao NAO e o numero: quem pareia so descobre o numero depois de ler o QR, e exigir que
// o usuario digitasse antes era pedir uma informacao que a propria sessao traz. A sessao tem id
// proprio, e o numero sai de sock.user.id quando conecta.
function normalizarId(id) {
  return String(id || '').trim().replace(/[^a-zA-Z0-9-]/g, '');
}

async function abrir(idBruto, { numeroEsperado = null } = {}) {
  const id = normalizarId(idBruto) || `s-${randomUUID()}`;

  const existente = sessoes.get(id);
  if (existente) {
    // Reparear uma caixa que ja existe: o numero dela passa a ser o unico aceito.
    if (numeroEsperado) existente.numeroEsperado = numeroEsperado;
    return existente;
  }

  const sessao = new Sessao(id, {
    raizDeAuth: RAIZ_DE_AUTH,
    numeroEsperado,
    aoReceber: (...args) => ganchos.aoReceber(...args),
    aoEcoar: (...args) => ganchos.aoEcoar(...args),
    aoMudarStatus: (...args) => ganchos.aoMudarStatus(...args),
  });

  sessoes.set(id, sessao);
  await sessao.conectar();
  logger.info({ sessao: id }, 'sessao aberta');
  return sessao;
}

function obter(idBruto) {
  return sessoes.get(normalizarId(idBruto)) || null;
}

async function fechar(idBruto) {
  const sessao = obter(idBruto);
  if (!sessao) return false;

  await sessao.desconectar();
  return true;
}

// Diferente de `fechar`, que desloga e reconecta para oferecer QR novo (reparear), aqui a sessao
// e descartada de vez: sai do mapa e a pasta de credenciais vai junto. A tela de conexao cria
// sessao antes de o numero parear, entao quem desiste no meio deixaria lixo conectando pra sempre.
async function remover(idBruto) {
  const id = normalizarId(idBruto);
  const sessao = sessoes.get(id);
  if (!sessao) return false;

  try {
    await sessao.sock?.logout();
  } catch (err) {
    logger.warn({ err: err.message, sessao: id }, 'erro no logout — descartando mesmo assim');
  }

  sessao.sock?.end?.();
  sessoes.delete(id);
  await fs.rm(sessao.pasta, { recursive: true, force: true }).catch(() => {});
  logger.info({ sessao: id }, 'sessao removida');
  return true;
}

function listar() {
  return [...sessoes.values()].map((s) => s.resumo());
}

// No boot, reabre o que ja foi pareado antes: cada subpasta de AUTH_DIR e uma sessao. Sem isso um
// restart deixaria os numeros fora do ar ate alguem chamar a API de novo.
async function retomarSessoesSalvas() {
  const itens = await fs.readdir(RAIZ_DE_AUTH, { withFileTypes: true }).catch(() => []);
  const pastas = itens.filter((i) => i.isDirectory() && normalizarId(i.name));

  for (const pasta of pastas) {
    try {
      await abrir(pasta.name);
    } catch (err) {
      logger.error({ err, sessao: pasta.name }, 'falha ao retomar sessao salva');
    }
  }

  logger.info({ quantidade: pastas.length }, 'sessoes retomadas do disco');
  return pastas.length;
}

module.exports = { abrir, obter, fechar, remover, listar, retomarSessoesSalvas, definirGanchos, normalizarId };
