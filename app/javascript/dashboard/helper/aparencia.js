/**
 * Aparência do painel: cor da interface e imagem de fundo da conversa.
 *
 * Tema e cor são coisas separadas, como no Windows: o tema (claro, escuro ou seguir o sistema)
 * decide se o fundo é claro ou escuro; a cor tinge a interface por cima dele. As duas convivem —
 * dá para ter tema escuro com cor rosa, ou tema claro com a mesma cor.
 *
 * Cada cor define só o matiz e a saturação. Os doze tons são derivados mantendo a progressão de
 * claridade da escala original do tema em uso (`_next-colors.scss`), e é isso que garante
 * legibilidade: os tons 1 a 8 fazem fundos e bordas, o 11 e o 12 são texto. Como a progressão
 * muda entre claro e escuro, a cor é recalculada quando o tema troca.
 */

// claridade de cada tom (--slate-1 .. --slate-12), espelhando as duas escalas do Chatwoot
const LUZ_ESCURA = [8, 11, 15, 18, 22, 26, 32, 42, 50, 56, 82, 94];
const LUZ_CLARA = [99, 97, 94, 91, 88, 84, 79, 71, 56, 50, 38, 22];

export const TEMAS_PERSONALIZADOS = {
  // `matiz` é a cor; `saturacao` vale para as superfícies (o realce tem a sua, mais viva);
  // `matizDoBot` fica longe do principal de propósito: é o que separa a bolha do bot da bolha
  // do agente sem precisar ler.
  rosa: { rotulo: 'Rosa', matiz: 335, saturacao: 42, matizDoBot: 300 },
  // matiz tirado do próprio logo da Mobílli (#DB7F2B); o bot puxa pro vermelho pra não se
  // confundir com o âmbar das notas privadas, que é vizinho do laranja
  laranja: {
    rotulo: 'Laranja',
    matiz: 29,
    saturacao: 40,
    matizDoBot: 352,
  },
  vermelho: { rotulo: 'Vermelho', matiz: 358, saturacao: 44, matizDoBot: 20 },
  roxo: { rotulo: 'Roxo', matiz: 276, saturacao: 42, matizDoBot: 320 },
  azul: { rotulo: 'Azul', matiz: 214, saturacao: 45, matizDoBot: 260 },
  amarelo: { rotulo: 'Amarelo', matiz: 45, saturacao: 48, matizDoBot: 20 },
};

export const temaEscuroAtivo = () => document.body.classList.contains('dark');

export const FUNDOS_PRONTOS = [
  { id: 'gradiente', url: '/brand/chat-backgrounds/gradiente.jpg' },
  { id: 'rio-crepusculo', url: '/brand/chat-backgrounds/rio-crepusculo.jpg' },
  { id: 'estrelas', url: '/brand/chat-backgrounds/estrelas.jpg' },
  { id: 'copacabana', url: '/brand/chat-backgrounds/copacabana.jpg' },
  { id: 'predios', url: '/brand/chat-backgrounds/predios.jpg' },
  { id: 'fachadas', url: '/brand/chat-backgrounds/fachadas.jpg' },
  { id: 'montanhas', url: '/brand/chat-backgrounds/montanhas.jpg' },
  { id: 'colina', url: '/brand/chat-backgrounds/colina.jpg' },
  { id: 'nova-york', url: '/brand/chat-backgrounds/nova-york.jpg' },
  { id: 'trilha', url: '/brand/chat-backgrounds/trilha.jpg' },
  { id: 'postes', url: '/brand/chat-backgrounds/postes.jpg' },
  { id: 'ceu-noturno', url: '/brand/chat-backgrounds/ceu-noturno.jpg' },
  { id: 'pao-de-acucar', url: '/brand/chat-backgrounds/pao-de-acucar.jpg' },
];

// Acima disto a imagem é reduzida no navegador antes de subir. O alvo é a mesma medida das
// imagens prontas: a tela nunca mostra mais que isso, então o excedente é só peso.
export const LARGURA_ALVO = 1920;
const QUALIDADE = 0.82;
const TAMANHO_SEM_MEXER = 600 * 1024;

/**
 * Reduz a imagem antes do envio, quando vale a pena.
 *
 * Arquivo pequeno e já dentro da medida volta intacto — reprocessar só tiraria qualidade. O
 * desenho vai sobre fundo branco porque a saída é JPEG: PNG com transparência viraria preto.
 *
 * @param {File} arquivo imagem escolhida
 * @returns {Promise<File>} a mesma imagem ou uma versão reduzida
 */
export const comprimirImagem = arquivo =>
  new Promise((resolve, reject) => {
    const imagem = new Image();
    const endereco = URL.createObjectURL(arquivo);

    imagem.onload = () => {
      URL.revokeObjectURL(endereco);
      const escala = Math.min(1, LARGURA_ALVO / imagem.width);
      if (escala === 1 && arquivo.size <= TAMANHO_SEM_MEXER) {
        resolve(arquivo);
        return;
      }

      const tela = document.createElement('canvas');
      tela.width = Math.round(imagem.width * escala);
      tela.height = Math.round(imagem.height * escala);
      const contexto = tela.getContext('2d');
      contexto.imageSmoothingEnabled = true;
      contexto.imageSmoothingQuality = 'high';
      contexto.fillStyle = '#ffffff';
      contexto.fillRect(0, 0, tela.width, tela.height);
      contexto.drawImage(imagem, 0, 0, tela.width, tela.height);

      tela.toBlob(
        dados => {
          if (!dados) {
            reject(new Error('compressao_falhou'));
            return;
          }
          const nome = arquivo.name.replace(/\.[^.]+$/, '') + '.jpg';
          resolve(new File([dados], nome, { type: 'image/jpeg' }));
        },
        'image/jpeg',
        QUALIDADE
      );
    };

    imagem.onerror = () => {
      URL.revokeObjectURL(endereco);
      reject(new Error('imagem_invalida'));
    };

    imagem.src = endereco;
  });

// tamanho sugerido para quem envia a própria imagem
export const MEDIDA_RECOMENDADA = { largura: 1920, altura: 1080 };

const hslParaRgb = (h, s, l) => {
  const saturacao = s / 100;
  const luz = l / 100;
  const k = n => (n + h / 30) % 12;
  const a = saturacao * Math.min(luz, 1 - luz);
  const canal = n =>
    Math.round(
      255 * (luz - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1))))
    );
  return `${canal(0)} ${canal(8)} ${canal(4)}`;
};

/**
 * Variáveis CSS de um tema personalizado.
 * @param {string} nome chave em TEMAS_PERSONALIZADOS
 * @returns {Object} mapa de variável -> valor
 */
// Contraste WCAG entre duas cores "r g b" — usado para o realce nunca sair claro demais.
const luminancia = cor => {
  const canais = cor.split(' ').map(valor => {
    const v = Number(valor) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * canais[0] + 0.7152 * canais[1] + 0.0722 * canais[2];
};

const contraste = (a, b) => {
  const x = luminancia(a);
  const y = luminancia(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
};

/**
 * Claridade do realce (botões cheios, que levam texto branco).
 *
 * Cores quentes são claras por natureza: o mesmo valor que funciona num rosa deixa um laranja
 * com texto branco ilegível. Em vez de calibrar cor a cor, desce a claridade até o contraste
 * com o branco alcançar 4.5 — assim qualquer cor nova entra sem precisar de ajuste manual.
 */
const luzDoRealce = (h, s, inicio) => {
  for (let luz = inicio; luz >= 20; luz -= 1) {
    if (contraste('255 255 255', hslParaRgb(h, s, luz)) >= 4.5) return luz;
  }
  return 20;
};

export const variaveisDoTema = (nome, escuro = temaEscuroAtivo()) => {
  const tema = TEMAS_PERSONALIZADOS[nome];
  if (!tema) return {};

  const { matiz: h, saturacao: s, matizDoBot: hBot } = tema;
  const luzes = escuro ? LUZ_ESCURA : LUZ_CLARA;
  // No claro a mesma saturação pesa mais, então as superfícies levam menos cor que no escuro —
  // e o texto leva MAIS: com pouca luz ele vira um vinho do mesmo matiz, que é o que dá liga ao
  // conjunto. Texto cinza no meio de uma interface colorida parece peça de outro jogo.
  const base = escuro ? s : Math.round(s * 0.57);
  const corDoTexto = escuro ? Math.max(s - 26, 8) : Math.round(s * 0.81);
  const variaveis = {};

  luzes.forEach((luz, indice) => {
    const tom = indice + 1;
    let saturacao = base;
    if (tom >= 11) {
      saturacao = escuro && tom === 11 ? Math.max(base - 16, 8) : corDoTexto;
    } else if (tom > 8) saturacao = base + (escuro ? 10 : 18);
    else if (!escuro && tom >= 5) saturacao = base + 8;
    variaveis[`--slate-${tom}`] = hslParaRgb(h, saturacao, luz);
  });

  Object.assign(
    variaveis,
    escuro
      ? {
          '--background-color': hslParaRgb(h, base, 13),
          '--surface-1': hslParaRgb(h, base, 10),
          '--surface-2': hslParaRgb(h, base, 12),
          '--surface-active': hslParaRgb(h, base, 26),
          // as bolhas não vêm da escala: cada tipo tem variável própria
          '--solid-blue': hslParaRgb(h, base + 18, 30),
          '--solid-blue-2': hslParaRgb(h, base, 14),
          '--solid-iris': hslParaRgb(hBot, base + 12, 30),
          // superfícies translúcidas (hover, divisórias) voltam ao branco: com a cor por baixo
          // elas ficavam pesadas demais
          '--alpha-1': '255, 255, 255, 0.07',
          '--alpha-2': '255, 255, 255, 0.11',
        }
      : {
          // três camadas: cartão quase branco, conteúdo um tom abaixo, lateral mais um — é a
          // diferença entre elas que dá profundidade, não a cor em si
          '--surface-2': hslParaRgb(h, Math.max(base - 6, 4), 99),
          '--background-color': hslParaRgb(h, base, 95),
          '--surface-1': hslParaRgb(h, base + 10, 92),
          '--surface-active': hslParaRgb(h, base + 18, 86),
          '--solid-blue': hslParaRgb(h, 52, 85),
          '--solid-blue-2': hslParaRgb(h, base, 97),
          '--solid-iris': hslParaRgb(hBot, 46, 87),
          '--alpha-1': '0, 0, 0, 0.04',
          '--alpha-2': '0, 0, 0, 0.07',
        }
  );

  // o realce é o mesmo nos dois temas: é a cor que a pessoa escolheu
  const luzRealce = luzDoRealce(h, 74, escuro ? 58 : 44);
  Object.assign(variaveis, {
    '--blue-9': hslParaRgb(h, 74, luzRealce),
    '--blue-10': hslParaRgb(h, 74, Math.max(luzRealce - 3, 18)),
    // o 11 é texto sobre fundo, não botão: pode ser mais claro no escuro
    '--blue-11': hslParaRgb(
      h,
      74,
      escuro ? Math.max(luzRealce + 6, 40) : luzRealce - 9
    ),
  });

  return variaveis;
};

const VARIAVEIS_APLICADAS = 'dados-tema-personalizado';
const ESTILO_DA_MARCA = 'cor-da-marca-propria';

const paraHex = (h, s, l) =>
  `#${hslParaRgb(h, s, l)
    .split(' ')
    .map(valor => Number(valor).toString(16).padStart(2, '0'))
    .join('')}`;

/**
 * Pinta o token de marca com a cor escolhida.
 *
 * `n-brand` é cor fixa compilada pelo Tailwind (não é variável CSS), então as variáveis não o
 * alcançam: sem isto, a interface fica rosa com os botões principais azuis.
 */
const aplicaCorDaMarca = nome => {
  let estilo = document.getElementById(ESTILO_DA_MARCA);
  const tema = TEMAS_PERSONALIZADOS[nome];

  if (!tema) {
    estilo?.remove();
    return;
  }

  if (!estilo) {
    estilo = document.createElement('style');
    estilo.id = ESTILO_DA_MARCA;
    document.head.appendChild(estilo);
  }

  const marca = paraHex(
    tema.matiz,
    74,
    luzDoRealce(tema.matiz, 74, temaEscuroAtivo() ? 58 : 44)
  );
  estilo.textContent = `
    .bg-n-brand { background-color: ${marca} !important; }
    .text-n-brand, .text-link { color: ${marca} !important; }
    .border-n-brand { border-color: ${marca} !important; }
    .ring-n-brand { --tw-ring-color: ${marca} !important; }
  `;
};

/**
 * Aplica (ou remove) um tema personalizado no documento.
 * @param {string} nome chave do tema; vazio volta ao tema padrão
 */
export const aplicaTemaPersonalizado = nome => {
  // As variáveis vão no <body>, não no <html>: o tema escuro do Chatwoot define as mesmas
  // variáveis na classe `.dark`, que fica no body — escrever no html deixaria o valor ser
  // sobrescrito logo abaixo, e a cor simplesmente não apareceria.
  const raiz = document.body;

  // limpa o que o tema anterior escreveu, senão sobra cor de um tema no outro
  const anteriores = raiz.getAttribute(VARIAVEIS_APLICADAS);
  if (anteriores) {
    anteriores
      .split(',')
      .forEach(variavel => raiz.style.removeProperty(variavel));
    raiz.removeAttribute(VARIAVEIS_APLICADAS);
  }

  const variaveis = variaveisDoTema(nome);
  const nomes = Object.keys(variaveis);
  if (!nomes.length) {
    document.body.removeAttribute('data-cor-propria');
    aplicaCorDaMarca('');
    return;
  }

  nomes.forEach(variavel =>
    raiz.style.setProperty(variavel, variaveis[variavel])
  );
  raiz.setAttribute(VARIAVEIS_APLICADAS, nomes.join(','));
  // a cor não decide claro ou escuro: quem manda nisso é o tema, e ela se adapta a ele
  document.body.setAttribute('data-cor-propria', nome);
  aplicaCorDaMarca(nome);
};

/**
 * Reaplica a cor em uso depois que o tema mudou.
 *
 * A escala derivada parte da progressão de claridade do tema: trocar de claro para escuro (ou o
 * contrário) sem recalcular deixaria texto claro sobre fundo claro.
 */
export const reaplicaCorAposTrocaDeTema = () => {
  const emUso = document.body.getAttribute('data-cor-propria');
  if (emUso) aplicaTemaPersonalizado(emUso);
};

let observandoTema = false;

/**
 * Mantém a cor coerente com o tema, aconteça o que acontecer.
 *
 * No carregamento da página a cor é aplicada antes de o claro/escuro ser decidido — e a escala
 * dela depende disso. Sem esta vigia, recarregar com uma cor ativa deixava a tela misturada:
 * escala clara por baixo de um painel escuro. Também cobre a troca pelo menu de comandos e a
 * mudança de preferência do sistema, que mexem na classe do body sem passar por aqui.
 */
export const vigiaTrocaDeTema = () => {
  if (observandoTema) return;

  observandoTema = true;
  new MutationObserver(reaplicaCorAposTrocaDeTema).observe(document.body, {
    attributes: true,
    attributeFilter: ['class'],
  });
};

/**
 * Aplica a imagem de fundo da conversa.
 * @param {string} url endereço da imagem; vazio remove o fundo
 */
export const aplicaFundoDoChat = url => {
  document.documentElement.style.setProperty(
    '--fundo-da-conversa',
    url ? `url('${url}')` : 'none'
  );
  // o marcador deixa o CSS saber que há imagem: sem ela, a caixa de resposta fica opaca como
  // sempre foi; com ela, abre passagem pra imagem continuar por baixo
  if (url) document.body.setAttribute('data-fundo-na-conversa', '');
  else document.body.removeAttribute('data-fundo-na-conversa');
};

// Quantas imagens próprias cada pessoa guarda. Passou disso, a mais antiga sai (e o arquivo é
// apagado de verdade no servidor): sem teto, cada troca deixaria um arquivo solto para sempre.
export const LIMITE_DE_ENVIOS = 3;

// claridade padrão do fundo: o meio da régua
export const CLARIDADE_PADRAO = 35;

/**
 * Claridade do fundo: regula o véu entre a imagem e as mensagens.
 *
 * Não mexe na imagem em si — o que muda é quanto da cor do tema fica por cima dela. Em 0 a
 * imagem quase some (véu fechado); em 100 ela aparece quase inteira. O véu nunca chega a zero
 * de propósito: sem nenhuma camada, texto claro sobre foto clara fica ilegível.
 *
 * @param {number} claridade de 0 a 100
 */
export const aplicaClaridadeDoFundo = claridade => {
  const valor = Number.isFinite(+claridade) ? +claridade : CLARIDADE_PADRAO;
  const topo = 1 - (Math.min(Math.max(valor, 0), 100) / 100) * 0.78;
  const raiz = document.documentElement;
  raiz.style.setProperty('--veu-da-conversa-topo', topo.toFixed(2));
  // o pé fica um pouco mais fechado: é onde ficam a caixa de resposta e as últimas mensagens
  raiz.style.setProperty(
    '--veu-da-conversa-base',
    Math.min(topo + 0.1, 1).toFixed(2)
  );
};
