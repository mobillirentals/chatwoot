/**
 * Marca da instalação nos textos da interface.
 *
 * O Chatwoot só troca o próprio nome nos poucos lugares em que alguém lembrou de chamar
 * `replaceInstallationName`; todo o resto do painel continua dizendo "Chatwoot" mesmo numa
 * instalação com nome próprio. Em vez de sair editando dezenas de arquivos de tradução — que
 * conflitariam em cada atualização do upstream —, a troca acontece na saída do i18n.
 */

// "Chatwoot" só é trocado com C maiúsculo e fora de endereço. Assim `chatwootSettings`, o token
// do widget, as classes de CSS e os links de documentação (app.chatwoot.com, chatwoot.com/terms)
// ficam intactos: trocar qualquer um deles quebraria instalação de widget e links.
const MENCAO = /Chatwoot(?![\w-]*\.(?:com|org|io|help|dev))/g;
const COLADO_EM_ENDERECO = /[\w./@-]/;

export const nomeDaInstalacao = () =>
  window?.globalConfig?.INSTALLATION_NAME || '';

export const comMarcaDaInstalacao = texto => {
  if (typeof texto !== 'string' || !texto.includes('Chatwoot')) return texto;

  const nome = nomeDaInstalacao();
  if (!nome || nome === 'Chatwoot') return texto;

  return texto.replace(MENCAO, (achado, posicao, inteiro) =>
    COLADO_EM_ENDERECO.test(inteiro[posicao - 1] || '') ? achado : nome
  );
};
