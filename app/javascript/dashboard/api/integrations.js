/* global axios */

import ApiClient from './ApiClient';

class IntegrationsAPI extends ApiClient {
  constructor() {
    super('integrations/apps', { accountScoped: true });
  }

  connectSlack(code) {
    return axios.post(`${this.baseUrl()}/integrations/slack`, { code });
  }

  updateSlack({ referenceId }) {
    return axios.patch(`${this.baseUrl()}/integrations/slack`, {
      reference_id: referenceId,
    });
  }

  listAllSlackChannels() {
    return axios.get(`${this.baseUrl()}/integrations/slack/list_all_channels`);
  }

  delete(integrationId) {
    return axios.delete(`${this.baseUrl()}/integrations/${integrationId}`);
  }

  createHook(hookData) {
    return axios.post(`${this.baseUrl()}/integrations/hooks`, hookData);
  }

  deleteHook(hookId) {
    return axios.delete(`${this.baseUrl()}/integrations/hooks/${hookId}`);
  }

  connectShopify({ shopDomain }) {
    return axios.post(`${this.baseUrl()}/integrations/shopify/auth`, {
      shop_domain: shopDomain,
    });
  }

  getWhatsappCheckerStatus() {
    return axios.get(`${this.baseUrl()}/integrations/whatsapp_number_checker`);
  }

  disconnectWhatsappChecker() {
    return axios.delete(
      `${this.baseUrl()}/integrations/whatsapp_number_checker`
    );
  }

  // responseType blob: essa chamada busca a imagem do QR code (nao JSON) — o componente
  // converte pra um object URL local pra exibir num <img>.
  getWhatsappCheckerQr() {
    return axios.get(
      `${this.baseUrl()}/integrations/whatsapp_number_checker/qr`,
      {
        responseType: 'blob',
      }
    );
  }
}

export default new IntegrationsAPI();
