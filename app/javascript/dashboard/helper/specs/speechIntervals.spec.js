import {
  buildSpeechIntervals,
  SPEECH_RMS_THRESHOLD,
  SPEECH_GAP_MS,
  SPEECH_MIN_MS,
} from '../speechIntervals';

const ALTO = SPEECH_RMS_THRESHOLD * 3;
const BAIXO = SPEECH_RMS_THRESHOLD / 3;

// Monta amostras de 100 em 100 ms a partir de uma descrição legível: 'sssFFFsss' onde F é fala.
const amostrar = (padrao, passo = 100) =>
  [...padrao].map((c, i) => ({ t: i * passo, rms: c === 'F' ? ALTO : BAIXO }));

describe('buildSpeechIntervals', () => {
  it('não acha fala no silêncio', () => {
    expect(buildSpeechIntervals(amostrar('ssssssss'))).toEqual([]);
  });

  it('acha um trecho de fala e devolve em segundos', () => {
    // Fala das amostras 2 a 6 → 200 ms a 600 ms.
    expect(buildSpeechIntervals(amostrar('ssFFFFFss'))).toEqual([
      { start: 0.2, end: 0.6 },
    ]);
  });

  // Respirada no meio da frase não pode virar dois turnos.
  it('não quebra o turno numa pausa curta', () => {
    const pausaCurta = Math.floor(SPEECH_GAP_MS / 100) - 1;
    const padrao = `FF${'s'.repeat(pausaCurta)}FF`;

    expect(buildSpeechIntervals(amostrar(padrao))).toHaveLength(1);
  });

  it('quebra o turno numa pausa longa', () => {
    const pausaLonga = Math.ceil(SPEECH_GAP_MS / 100) + 2;
    // Rajadas de 5 amostras (400 ms) para passarem do mínimo de duração; o alvo aqui é a pausa.
    const padrao = `FFFFF${'s'.repeat(pausaLonga)}FFFFF`;

    expect(buildSpeechIntervals(amostrar(padrao))).toHaveLength(2);
  });

  // Estalo isolado não é fala: sem este corte, qualquer clique vira um turno no gráfico.
  it('descarta trecho curto demais', () => {
    const umaAmostra = buildSpeechIntervals(amostrar('ssFss'));

    expect(umaAmostra).toEqual([]);
    expect(SPEECH_MIN_MS).toBeGreaterThan(100);
  });

  // É o caso que motivou tudo: quem fala depois tem silêncio no começo, e esse silêncio precisa
  // sobreviver — é ele que diz que a fala aconteceu lá na frente, não em zero.
  it('preserva o silêncio inicial, que é o que o whisper joga fora', () => {
    const [primeiro] = buildSpeechIntervals(amostrar(`${'s'.repeat(90)}FFFFF`));

    expect(primeiro.start).toBe(9);
  });

  it('aceita limiares próprios', () => {
    const amostras = [
      { t: 0, rms: 0.5 },
      { t: 100, rms: 0.5 },
      { t: 200, rms: 0.5 },
      { t: 300, rms: 0.5 },
    ];

    expect(buildSpeechIntervals(amostras, { threshold: 0.9 })).toEqual([]);
  });
});
