const BASE_URL    = (process.env.CHATWOOT_BASE_URL || 'http://rails:3000').replace(/\/$/, '');
const BOT_TOKEN   = process.env.BOT_TOKEN;
const ACCOUNT_ID  = process.env.ACCOUNT_ID || '1';

async function request(method, path, body = null) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json', api_access_token: BOT_TOKEN },
  };
  if (body) opts.body = JSON.stringify(body);

  const res = await fetch(`${BASE_URL}${path}`, opts);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`[api] ${method} ${path} → ${res.status}: ${text}`);
  }
  return res.json().catch(() => ({}));
}

// ─── Mensagens ────────────────────────────────────────────────────────────────

function sendMessage(conversationId, content) {
  return request('POST', `/api/v1/accounts/${ACCOUNT_ID}/conversations/${conversationId}/messages`, {
    content,
    message_type: 'outgoing',
  });
}

// ─── Status da conversa ───────────────────────────────────────────────────────

function handoff(conversationId) {
  return request('POST', `/api/v1/accounts/${ACCOUNT_ID}/conversations/${conversationId}/toggle_status`, {
    status: 'open',
  });
}

function resolve(conversationId) {
  return request('POST', `/api/v1/accounts/${ACCOUNT_ID}/conversations/${conversationId}/toggle_status`, {
    status: 'resolved',
  });
}

// ─── Atribuição ───────────────────────────────────────────────────────────────

function addLabel(conversationId, label) {
  return request('POST', `/api/v1/accounts/${ACCOUNT_ID}/conversations/${conversationId}/labels`, {
    labels: [label],
  });
}

function assignTeam(conversationId, teamId) {
  return request('POST', `/api/v1/accounts/${ACCOUNT_ID}/conversations/${conversationId}/assignments`, {
    team_id: teamId,
  });
}

// ─── Times ────────────────────────────────────────────────────────────────────

function getTeams() {
  return request('GET', `/api/v1/accounts/${ACCOUNT_ID}/teams`);
}

module.exports = { sendMessage, handoff, resolve, addLabel, assignTeam, getTeams };
