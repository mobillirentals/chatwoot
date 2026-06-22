// Máquina de estados por conversa (in-memory).
// Para persistência entre reinicializações, substitua o Map por Redis.

const STATES = {
  INITIAL:                    'INITIAL',
  MAIN_MENU:                  'MAIN_MENU',
  FINANCEIRO_MENU:            'FINANCEIRO_MENU',
  AJUDA_MENU:                 'AJUDA_MENU',
  OFICINA_MENU:               'OFICINA_MENU',
  DUVIDAS_MENU:               'DUVIDAS_MENU',
  OUVIDORIA_MENU:             'OUVIDORIA_MENU',
  OUVIDORIA_COLLECT:          'OUVIDORIA_COLLECT',
  URGENCIAS_MENU:             'URGENCIAS_MENU',
  SINISTRO_COLLECT_NAME:      'SINISTRO_COLLECT_NAME',
  SINISTRO_COLLECT_PLATE:     'SINISTRO_COLLECT_PLATE',
  SINISTRO_COLLECT_LOCATION:  'SINISTRO_COLLECT_LOCATION',
  SINISTRO_COLLECT_REFERENCE: 'SINISTRO_COLLECT_REFERENCE',
  DONE:                       'DONE',
};

/** @type {Map<string, { state: string, data: object, updatedAt: number }>} */
const store = new Map();

function get(conversationId) {
  return store.get(String(conversationId)) || null;
}

function set(conversationId, newState, extraData = {}) {
  const prev = get(conversationId) || { data: {} };
  store.set(String(conversationId), {
    state:     newState,
    data:      { ...prev.data, ...extraData },
    updatedAt: Date.now(),
  });
}

function clear(conversationId) {
  store.delete(String(conversationId));
}

module.exports = { STATES, get, set, clear };
