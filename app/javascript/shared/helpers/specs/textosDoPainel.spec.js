import { comAjustesDeTexto } from 'shared/helpers/textosDoPainel';

describe('comAjustesDeTexto', () => {
  beforeEach(() => {
    window.globalConfig = { INSTALLATION_NAME: 'Chatmobílli' };
  });

  it('troca o nome do produto nos textos que a pessoa lê', () => {
    expect(comAjustesDeTexto('Entrar no Chatwoot')).toBe(
      'Entrar no Chatmobílli'
    );
    expect(comAjustesDeTexto('Desenvolvido por Chatwoot')).toBe(
      'Desenvolvido por Chatmobílli'
    );
  });

  it('não mexe em endereço, que trocado vira link quebrado', () => {
    const texto = 'Acesse https://www.chatwoot.com/terms e app.chatwoot.com/hc';
    expect(comAjustesDeTexto(texto)).toBe(texto);
    expect(comAjustesDeTexto('Veja Chatwoot.com/docs')).toBe(
      'Veja Chatwoot.com/docs'
    );
  });

  it('não mexe no código do widget, que trocado quebra a instalação', () => {
    const script = 'window.chatwootSettings = {options};';
    expect(comAjustesDeTexto(script)).toBe(script);
    expect(comAjustesDeTexto('chatwoot_website_token')).toBe(
      'chatwoot_website_token'
    );
  });

  it('deixa o texto como está quando a instalação não tem nome próprio', () => {
    window.globalConfig = { INSTALLATION_NAME: '' };
    expect(comAjustesDeTexto('Entrar no Chatwoot')).toBe('Entrar no Chatwoot');

    window.globalConfig = { INSTALLATION_NAME: 'Chatwoot' };
    expect(comAjustesDeTexto('Entrar no Chatwoot')).toBe('Entrar no Chatwoot');
  });

  it('devolve o valor intocado quando não é texto', () => {
    expect(comAjustesDeTexto(undefined)).toBe(undefined);
    expect(comAjustesDeTexto(42)).toBe(42);
  });

  it('chama o Captain pelo nome, não pela tradução', () => {
    expect(comAjustesDeTexto('Carregando console do Capitão...')).toBe(
      'Carregando console do Captain...'
    );
    expect(comAjustesDeTexto('O Capitão não está disponível')).toBe(
      'O Captain não está disponível'
    );
  });

  it('corrige o menu e o título da lista, que colidiam com o nome dos canais', () => {
    expect(comAjustesDeTexto('Caixa de Entrada', 'SIDEBAR.INBOX')).toBe(
      'Notificações'
    );
    expect(comAjustesDeTexto('Caixa de Entrada', 'INBOX.LIST.TITLE')).toBe(
      'Notificações'
    );
  });

  it('não mexe em "Caixa de Entrada" fora daquele item de menu', () => {
    expect(comAjustesDeTexto('Caixa de Entrada', 'CALLS.FILTER.INBOX')).toBe(
      'Caixa de Entrada'
    );
    expect(comAjustesDeTexto('Caixa de Entrada')).toBe('Caixa de Entrada');
  });

  it('deixa a chave em paz quando o upstream mudar o texto', () => {
    expect(comAjustesDeTexto('My Inbox', 'SIDEBAR.INBOX')).toBe('My Inbox');
  });
});
