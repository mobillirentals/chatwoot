/**
 * Ajustes nos textos da interface, aplicados na saída do i18n (`postTranslation`).
 *
 * Três coisas moram aqui, e todas pela mesma razão: corrigi-las nos arquivos de tradução
 * significaria editar dezenas de linhas do upstream, que conflitariam em cada atualização.
 *
 * 1. O nome da instalação. O Chatwoot só troca o próprio nome nos poucos lugares em que alguém
 *    lembrou de chamar `replaceInstallationName`; o resto do painel continua dizendo "Chatwoot".
 * 2. O nome do Captain. Produto não se traduz, e a tradução em português virou "Capitão".
 * 3. Correções pontuais de tradução, presas à chave.
 */

// "Chatwoot" só é trocado com C maiúsculo e fora de endereço. Assim `chatwootSettings`, o token
// do widget, as classes de CSS e os links de documentação (app.chatwoot.com, chatwoot.com/terms)
// ficam intactos: trocar qualquer um deles quebraria instalação de widget e links.
const MENCAO = /Chatwoot(?![\w-]*\.(?:com|org|io|help|dev))/g;
const COLADO_EM_ENDERECO = /[\w./@-]/;

// O Captain é o nome do produto, como Chatwoot: em inglês ninguém chama de "Captain" por acaso.
// A tradução pt-BR do upstream o rebatizou de "Capitão" em 37 lugares (menu, console, avisos de
// limite, relatório de mensagem da IA), e aí o nome do produto muda conforme o idioma de quem
// olha — o que confunde na hora de procurar documentação ou falar com o suporte.
const NOME_TRADUZIDO = /Capitão/g;

// Correção presa à chave E ao texto de origem: só vale enquanto o upstream traz aquele texto
// naquele idioma. Em inglês a chave já diz "My Inbox" (não casa, nada muda), e se a tradução
// mudar um dia o pior que acontece é voltar ao texto do upstream.
const CORRECOES = {
  // "Caixa de Entrada" é o nome das CAIXAS (os canais: WhatsApp, site, e-mail) em todo o resto do
  // painel. Este item do menu é outra coisa — são as notificações de quem está usando, e o texto
  // original diz "My Inbox". Com o mesmo nome dos canais, a tela parece uma lista de conversas.
  'SIDEBAR.INBOX': { de: 'Caixa de Entrada', para: 'Notificações' },
};

export const nomeDaInstalacao = () =>
  window?.globalConfig?.INSTALLATION_NAME || '';

const comMarcaDaInstalacao = texto => {
  if (!texto.includes('Chatwoot')) return texto;

  const nome = nomeDaInstalacao();
  if (!nome || nome === 'Chatwoot') return texto;

  return texto.replace(MENCAO, (achado, posicao, inteiro) =>
    COLADO_EM_ENDERECO.test(inteiro[posicao - 1] || '') ? achado : nome
  );
};

export const comAjustesDeTexto = (texto, chave) => {
  if (typeof texto !== 'string') return texto;

  const correcao = CORRECOES[chave];
  if (correcao && texto === correcao.de) return correcao.para;

  return comMarcaDaInstalacao(texto.replace(NOME_TRADUZIDO, 'Captain'));
};
