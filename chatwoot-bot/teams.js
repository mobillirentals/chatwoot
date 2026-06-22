// Carrega os times do Chatwoot na inicialização e expõe lookup por nome.
const api = require('./api');

/** @type {Record<string, number>} nome em lowercase → id */
let byName = {};

async function load() {
  try {
    const teams = await api.getTeams();
    byName = {};
    (Array.isArray(teams) ? teams : []).forEach(t => {
      byName[t.name.toLowerCase().trim()] = t.id;
    });
    console.log(`[teams] ${Object.keys(byName).length} times carregados:`, Object.keys(byName));
  } catch (e) {
    console.warn('[teams] falha ao carregar times:', e.message);
  }
}

/** Retorna o id do time pelo nome (case-insensitive) ou null se não encontrado. */
function getIdByName(name) {
  return byName[name.toLowerCase().trim()] ?? null;
}

module.exports = { load, getIdByName };
