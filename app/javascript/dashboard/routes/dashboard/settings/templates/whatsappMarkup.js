// Marcação de texto do WhatsApp.
//
// O WhatsApp formata com caracteres, não com HTML: *negrito*, _itálico_, ~tachado~ e ```mono```.
// Ela vale no CORPO do modelo — a Meta não formata cabeçalho nem rodapé, e deixar a pessoa marcar
// ali só produziria asterisco literal na mensagem do cliente.

export const MARKS = {
  BOLD: '*',
  ITALIC: '_',
  STRIKE: '~',
  MONO: '```',
};

// Envolve a seleção com o marcador, ou tira se já estiver marcada. Sem seleção, insere o par e
// deixa o cursor no meio, que é o que a pessoa espera ao clicar em "negrito" antes de escrever.
export const wrapSelection = (texto, inicio, fim, marcador) => {
  const valor = texto || '';
  const tamanho = marcador.length;
  const selecionado = valor.slice(inicio, fim);

  // Marcado por dentro: *texto* está selecionado inteiro, marcadores incluídos.
  if (
    selecionado.length >= tamanho * 2 &&
    selecionado.startsWith(marcador) &&
    selecionado.endsWith(marcador)
  ) {
    const nu = selecionado.slice(tamanho, -tamanho);
    return {
      texto: valor.slice(0, inicio) + nu + valor.slice(fim),
      inicio,
      fim: inicio + nu.length,
    };
  }

  // Marcado por fora: o texto está selecionado, mas os marcadores ficaram de fora da seleção.
  const antes = valor.slice(Math.max(0, inicio - tamanho), inicio);
  const depois = valor.slice(fim, fim + tamanho);
  if (antes === marcador && depois === marcador) {
    return {
      texto:
        valor.slice(0, inicio - tamanho) +
        selecionado +
        valor.slice(fim + tamanho),
      inicio: inicio - tamanho,
      fim: fim - tamanho,
    };
  }

  return {
    texto:
      valor.slice(0, inicio) +
      marcador +
      selecionado +
      marcador +
      valor.slice(fim),
    inicio: inicio + tamanho,
    fim: fim + tamanho,
  };
};

const escaparHtml = texto =>
  texto.replace(
    /[&<>"']/g,
    caractere =>
      ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
      })[caractere]
  );

// A prévia precisa mostrar o texto formatado, não os asteriscos: é o que o cliente vai ver.
// O escape vem antes de qualquer substituição, então as tags abaixo são as únicas no resultado.
export const renderMarkup = texto =>
  escaparHtml(texto || '')
    .replace(/```([^`]+)```/g, '<code>$1</code>')
    .replace(/(^|\s)\*([^*\n]+)\*/g, '$1<strong>$2</strong>')
    .replace(/(^|\s)_([^_\n]+)_/g, '$1<em>$2</em>')
    .replace(/(^|\s)~([^~\n]+)~/g, '$1<s>$2</s>');
