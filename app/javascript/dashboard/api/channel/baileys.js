/* global axios */
import ApiClient from '../ApiClient';

// WhatsApp não oficial, pareado por QR code. O painel nunca fala com a ponte diretamente — ela é
// interna e não está publicada —, então tudo passa pelo Rails, que também é quem guarda o segredo.
class BaileysAPI extends ApiClient {
  constructor() {
    super('whatsapp', { accountScoped: true });
  }

  // Abre (ou reaproveita) a sessão daquele número na ponte.
  abrirSessao(phoneNumber) {
    return axios.post(`${this.baseUrl()}/whatsapp/baileys/sessions`, {
      phone_number: phoneNumber,
    });
  }

  obterSessao(phoneNumber) {
    return axios.get(
      `${this.baseUrl()}/whatsapp/baileys/sessions/${phoneNumber}`
    );
  }

  obterQr(phoneNumber) {
    return axios.get(
      `${this.baseUrl()}/whatsapp/baileys/sessions/${phoneNumber}/qr`
    );
  }

  // Só depois do pareamento: a validação do canal confere na ponte se o número bate.
  criarCaixa(params) {
    return axios.post(`${this.baseUrl()}/whatsapp/baileys/connect`, params);
  }
}

export default new BaileysAPI();
