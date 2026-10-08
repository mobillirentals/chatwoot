import { MARKS, wrapSelection, renderMarkup } from '../whatsappMarkup';

describe('wrapSelection', () => {
  it('envolve a selecao com o marcador', () => {
    const r = wrapSelection('ola mundo', 4, 9, MARKS.BOLD);

    expect(r.texto).toBe('ola *mundo*');
    expect([r.inicio, r.fim]).toEqual([5, 10]);
  });

  // Clicar de novo tem que desfazer, senao a pessoa acumula ** e a Meta recusa o modelo.
  it('tira a marcacao quando os marcadores estao dentro da selecao', () => {
    const r = wrapSelection('ola *mundo*', 4, 11, MARKS.BOLD);

    expect(r.texto).toBe('ola mundo');
    expect([r.inicio, r.fim]).toEqual([4, 9]);
  });

  it('tira a marcacao quando os marcadores ficaram de fora da selecao', () => {
    const r = wrapSelection('ola *mundo*', 5, 10, MARKS.BOLD);

    expect(r.texto).toBe('ola mundo');
    expect([r.inicio, r.fim]).toEqual([4, 9]);
  });

  it('sem selecao, insere o par e poe o cursor no meio', () => {
    const r = wrapSelection('ola ', 4, 4, MARKS.ITALIC);

    expect(r.texto).toBe('ola __');
    expect([r.inicio, r.fim]).toEqual([5, 5]);
  });

  it('funciona com o marcador de monoespacado, que tem tres caracteres', () => {
    const r = wrapSelection('codigo', 0, 6, MARKS.MONO);

    expect(r.texto).toBe('```codigo```');
    expect([r.inicio, r.fim]).toEqual([3, 9]);
  });
});

describe('renderMarkup', () => {
  it('converte a marcacao do WhatsApp', () => {
    expect(renderMarkup('*forte* e _torto_ e ~fora~')).toBe(
      '<strong>forte</strong> e <em>torto</em> e <s>fora</s>'
    );
  });

  it('converte monoespacado', () => {
    expect(renderMarkup('use ```ABC123```')).toBe('use <code>ABC123</code>');
  });

  // O texto e de quem escreveu, mas vai para dentro de v-html: tem que sair escapado.
  it('escapa html antes de qualquer coisa', () => {
    expect(renderMarkup('<img src=x onerror=alert(1)>')).toBe(
      '&lt;img src=x onerror=alert(1)&gt;'
    );
  });

  it('nao marca sublinhado no meio de palavra, como em nome_de_modelo', () => {
    expect(renderMarkup('veja aviso_de_pagamento')).toBe(
      'veja aviso_de_pagamento'
    );
  });
});
