// Detecção de fala por lado da chamada, medida no navegador.
//
// Por que isto existe: o whisper **descarta o silêncio inicial** e começa a contar do zero. Medido
// com um arquivo de 9 s de silêncio seguidos de fala — ele reportou o trecho em 0,00 s. Logo, os
// tempos que ele devolve para dois arquivos diferentes NÃO são comparáveis, e ordenar os dois
// lados por eles produz um diálogo fictício: quem falou depois aparece no começo.
//
// O único relógio confiável é o do navegador, que grava os dois lados ao mesmo tempo. Aqui mora a
// parte que pode errar em silêncio — transformar energia em intervalos de fala. O encaixe do texto
// nesses intervalos acontece no servidor, onde os trechos do whisper chegam.

// Abaixo disto é ruído de fundo, não fala. Valor conservador: prefere deixar passar silêncio a
// cortar fala baixa, porque fala perdida some do histórico e silêncio a mais só suja o gráfico.
export const SPEECH_RMS_THRESHOLD = 0.012;
// Pausa curta no meio de uma frase não encerra o turno.
export const SPEECH_GAP_MS = 600;
// Estalo isolado não é fala.
export const SPEECH_MIN_MS = 250;

// `amostras` é [{ t, rms }] em ordem de tempo, `t` em ms desde o início da gravação.
export const buildSpeechIntervals = (
  amostras,
  {
    threshold = SPEECH_RMS_THRESHOLD,
    gap = SPEECH_GAP_MS,
    min = SPEECH_MIN_MS,
  } = {}
) => {
  const intervalos = [];
  let atual = null;

  // Amostra abaixo do limiar não encerra o turno na hora: quem encerra é a distância até a
  // próxima fala, comparada com a folga. Assim uma respirada no meio da frase não vira dois turnos.
  amostras.forEach(({ t, rms }) => {
    if (rms < threshold) return;

    if (atual && t - atual.end <= gap) {
      atual.end = t;
      return;
    }
    if (atual) intervalos.push(atual);
    atual = { start: t, end: t };
  });
  if (atual) intervalos.push(atual);

  return intervalos
    .filter(({ start, end }) => end - start >= min)
    .map(({ start, end }) => ({
      start: Number((start / 1000).toFixed(2)),
      end: Number((end / 1000).toFixed(2)),
    }));
};
