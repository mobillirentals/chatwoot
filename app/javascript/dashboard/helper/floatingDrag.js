// Limites de arrasto de um painel flutuante.
//
// Isolado do componente de propósito: é a parte que erra em silêncio. Um deslocamento sem limite
// deixa o painel sair da tela, e aí não há como trazê-lo de volta — some com os controles da
// chamada junto.

export const DRAG_MARGIN = 8;

// `base` é a posição do elemento SEM deslocamento nenhum (a que o CSS daria sozinho), em
// coordenadas de viewport. O deslocamento é somado a ela, então basta garantir que o retângulo
// resultante continue dentro da janela, com uma margem.
export const clampDragOffset = (
  offset,
  base,
  viewport,
  margin = DRAG_MARGIN
) => {
  const limitar = (valor, minimo, maximo) =>
    // Painel maior que a janela: o mínimo passa do máximo e um clamp ingênuo inverteria os
    // limites. Nesse caso vale encostar no topo/esquerda, que é onde ficam os controles.
    maximo < minimo ? minimo : Math.min(Math.max(valor, minimo), maximo);

  return {
    x: limitar(
      offset.x,
      margin - base.left,
      viewport.width - margin - base.width - base.left
    ),
    y: limitar(
      offset.y,
      margin - base.top,
      viewport.height - margin - base.height - base.top
    ),
  };
};

// Controles não podem virar alça de arrasto: um clique que começa num botão tem que continuar
// sendo clique, senão desligar a chamada vira sorteio.
export const isDragHandle = target =>
  !target?.closest?.('button, a, input, select, textarea, [role="button"]');
