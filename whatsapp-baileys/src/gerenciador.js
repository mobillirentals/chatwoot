const fs = require('fs/promises');
const pino = require('pino');
const { Sessao } = require('./sessao');

const logger = pino({ level: process.env.LOG_LEVEL || 'warn' });

const RAIZ_DE_AUTH = process.env.AUTH_DIR || './auth_session';

const sessoes = new Map();
let ganchos = { aoReceber: async () => {}, aoEcoar: async () => {}, aoMudarStatus: async () => {} };

function definirGanchos(novos) {
  ganchos = { ...ganchos, ...novos };
}

// O id da sessao e o numero da caixa, so digitos. Usar o proprio numero evita um campo a mais no
// provider_config e torna obvio, olhando a pasta, de quem e cada credencial.
function normalizarId(id) {
  return String(id || '').replace(/\D/g, '');
}

async function abrir(idBruto) {
  const id = normalizarId(idBruto);
  if (!id) throw new Error('id de sessao invalido');

  const existente = sessoes.get(id);
  if (existente) return existente;

  const sessao = new Sessao(id, {
    raizDeAuth: RAIZ_DE_AUTH,
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

module.exports = { abrir, obter, fechar, listar, retomarSessoesSalvas, definirGanchos, normalizarId };
