import { clampDragOffset, isDragHandle, DRAG_MARGIN } from '../floatingDrag';

// Painel de 400x200 encostado no canto inferior direito de uma janela 1200x800, como o widget de
// chamada nasce.
const base = { left: 784, top: 584, width: 400, height: 200 };
const viewport = { width: 1200, height: 800 };

describe('clampDragOffset', () => {
  it('deixa passar um arrasto que cabe na tela', () => {
    expect(clampDragOffset({ x: -100, y: -50 }, base, viewport)).toEqual({
      x: -100,
      y: -50,
    });
  });

  // Sem limite o painel sai da tela e leva os controles da chamada junto: não há como desligar
  // nem trazer de volta.
  it('nao deixa sair pela esquerda nem pelo topo', () => {
    expect(clampDragOffset({ x: -5000, y: -5000 }, base, viewport)).toEqual({
      x: DRAG_MARGIN - base.left,
      y: DRAG_MARGIN - base.top,
    });
  });

  it('nao deixa sair pela direita nem por baixo', () => {
    const { x, y } = clampDragOffset({ x: 5000, y: 5000 }, base, viewport);

    expect(base.left + x + base.width).toBe(viewport.width - DRAG_MARGIN);
    expect(base.top + y + base.height).toBe(viewport.height - DRAG_MARGIN);
  });

  // Janela menor que o painel inverteria os limites, e um clamp ingênuo devolveria o canto
  // errado — jogando o painel para fora justamente na tela onde ele menos cabe.
  it('encosta no topo e na esquerda quando o painel e maior que a janela', () => {
    const apertada = { width: 300, height: 150 };

    expect(clampDragOffset({ x: 999, y: 999 }, base, apertada)).toEqual({
      x: DRAG_MARGIN - base.left,
      y: DRAG_MARGIN - base.top,
    });
  });

  it('aceita uma margem propria', () => {
    expect(clampDragOffset({ x: -5000, y: 0 }, base, viewport, 40).x).toBe(
      40 - base.left
    );
  });
});

describe('isDragHandle', () => {
  const alvo = seletorQueCasa => ({
    closest: s => (s.includes(seletorQueCasa) ? {} : null),
  });

  // Um clique que começa num botão tem que continuar sendo clique: desligar a chamada não pode
  // virar sorteio entre arrastar e acionar.
  it('recusa controles', () => {
    expect(isDragHandle(alvo('button'))).toBe(false);
  });

  it('aceita o resto do painel', () => {
    expect(isDragHandle({ closest: () => null })).toBe(true);
  });

  it('nao quebra sem alvo', () => {
    expect(isDragHandle(null)).toBe(true);
  });
});

// O caso que apareceu em producao: o deslocamento guardado veio de uma janela maior, e aplicado
// numa tela menor jogava o painel inteiro para fora -- a chamada tocava sem nada aparecer.
describe('posicao guardada de uma janela maior', () => {
  const origem = { left: 1000, top: 700, width: 400, height: 220 };

  it('traz o painel de volta para dentro da tela menor', () => {
    const guardado = { x: -200, y: -400 };
    const janelaPequena = { width: 1280, height: 720 };

    const ajustado = clampDragOffset(guardado, origem, janelaPequena);
    const direita = origem.left + ajustado.x + origem.width;
    const baixo = origem.top + ajustado.y + origem.height;

    expect(origem.left + ajustado.x).toBeGreaterThanOrEqual(0);
    expect(origem.top + ajustado.y).toBeGreaterThanOrEqual(0);
    expect(direita).toBeLessThanOrEqual(janelaPequena.width);
    expect(baixo).toBeLessThanOrEqual(janelaPequena.height);
  });

  it('nao mexe num deslocamento que ainda cabe', () => {
    const cabe = { x: -100, y: -100 };

    expect(
      clampDragOffset(cabe, origem, { width: 1920, height: 1080 })
    ).toEqual(cabe);
  });
});
