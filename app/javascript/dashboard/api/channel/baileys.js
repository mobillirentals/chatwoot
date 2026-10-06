/* global axios */
import ApiClient from '../ApiClient';

// WhatsApp não oficial, pareado por QR code. O painel nunca fala com a ponte diretamente — ela é
// interna e não está publicada —, então tudo passa pelo Rails, que também é quem guarda o segredo.
class BaileysAPI extends ApiClient {
  constructor() {
    super('whatsapp', { accountScoped: true });
  }

  // Abre uma sessão nova e devolve o id dela. Sem número: quem pareia só descobre o número ao ler
  // o QR, e a sessão o informa de volta assim que conecta.
  abrirSessao() {
    return axios.post(`${this.baseUrl()}/whatsapp/baileys/sessions`, {});
  }

  obterSessao(sessionId) {
    return axios.get(
      `${this.baseUrl()}/whatsapp/baileys/sessions/${sessionId}`
    );
  }

  obterQr(sessionId) {
    return axios.get(
      `${this.baseUrl()}/whatsapp/baileys/sessions/${sessionId}/qr`
    );
  }

  // Só depois do pareamento: a validação do canal confere na ponte se o número bate.
  criarCaixa(params) {
    return axios.post(`${this.baseUrl()}/whatsapp/baileys/connect`, params);
  }

  // Caixa que já existe: acompanhar a conexão e reparear quando ela cair.
  estadoDaCaixa(inboxId) {
    return axios.get(`${this.baseUrl()}/whatsapp/baileys/inboxes/${inboxId}`);
  }

  qrDaCaixa(inboxId) {
    return axios.get(
      `${this.baseUrl()}/whatsapp/baileys/inboxes/${inboxId}/qr`
    );
  }

  reconectarCaixa(inboxId) {
    return axios.post(
      `${this.baseUrl()}/whatsapp/baileys/inboxes/${inboxId}/reconnect`
    );
  }
}

export default new BaileysAPI();
