// Fuso horário de Brasília (UTC-3, sem horário de verão desde 2019)
const TZ = 'America/Sao_Paulo';

// Feriados nacionais fixos (MM-DD)
const FIXED = [
  '01-01', // Confraternização Universal
  '04-21', // Tiradentes
  '05-01', // Dia do Trabalho
  '09-07', // Independência do Brasil
  '10-12', // Nossa Senhora Aparecida
  '11-02', // Finados
  '11-15', // Proclamação da República
  '11-20', // Consciência Negra
  '12-25', // Natal
];

// Feriados móveis (YYYY-MM-DD) — Sexta Santa, Corpus Christi
const MOVEABLE = [
  '2025-04-18', '2025-06-19',
  '2026-04-03', '2026-06-04',
  '2027-03-26', '2027-05-27',
];

function nowInBrasilia() {
  return new Date(new Date().toLocaleString('en-US', { timeZone: TZ }));
}

function isHoliday(d) {
  const mmdd = `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  const full  = `${d.getFullYear()}-${mmdd}`;
  return FIXED.includes(mmdd) || MOVEABLE.includes(full);
}

/**
 * Retorna true se agora estiver dentro do horário comercial.
 * Seg–Sex: 08h–18h | Sáb: 08h–12h | Dom + feriados: fechado
 */
function isBusinessHours() {
  const now  = nowInBrasilia();
  const dow  = now.getDay();       // 0 = domingo
  const mins = now.getHours() * 60 + now.getMinutes();

  if (isHoliday(now)) return false;
  if (dow >= 1 && dow <= 5) return mins >= 480 && mins < 1080; // 08:00–18:00
  if (dow === 6)            return mins >= 480 && mins < 720;  // 08:00–12:00
  return false;
}

module.exports = { isBusinessHours };
