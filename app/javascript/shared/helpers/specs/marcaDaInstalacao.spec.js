import { comMarcaDaInstalacao } from 'shared/helpers/marcaDaInstalacao';

describe('comMarcaDaInstalacao', () => {
  beforeEach(() => {
    window.globalConfig = { INSTALLATION_NAME: 'Chatmobílli' };
  });

  it('troca o nome do produto nos textos que a pessoa lê', () => {
    expect(comMarcaDaInstalacao('Entrar no Chatwoot')).toBe(
      'Entrar no Chatmobílli'
    );
    expect(comMarcaDaInstalacao('Desenvolvido por Chatwoot')).toBe(
      'Desenvolvido por Chatmobílli'
    );
  });

  it('não mexe em endereço, que trocado vira link quebrado', () => {
    const texto = 'Acesse https://www.chatwoot.com/terms e app.chatwoot.com/hc';
    expect(comMarcaDaInstalacao(texto)).toBe(texto);
    expect(comMarcaDaInstalacao('Veja Chatwoot.com/docs')).toBe(
      'Veja Chatwoot.com/docs'
    );
  });

  it('não mexe no código do widget, que trocado quebra a instalação', () => {
    const script = 'window.chatwootSettings = {options};';
    expect(comMarcaDaInstalacao(script)).toBe(script);
    expect(comMarcaDaInstalacao('chatwoot_website_token')).toBe(
      'chatwoot_website_token'
    );
  });

  it('deixa o texto como está quando a instalação não tem nome próprio', () => {
    window.globalConfig = { INSTALLATION_NAME: '' };
    expect(comMarcaDaInstalacao('Entrar no Chatwoot')).toBe(
      'Entrar no Chatwoot'
    );

    window.globalConfig = { INSTALLATION_NAME: 'Chatwoot' };
    expect(comMarcaDaInstalacao('Entrar no Chatwoot')).toBe(
      'Entrar no Chatwoot'
    );
  });

  it('devolve o valor intocado quando não é texto', () => {
    expect(comMarcaDaInstalacao(undefined)).toBe(undefined);
    expect(comMarcaDaInstalacao(42)).toBe(42);
  });
});
