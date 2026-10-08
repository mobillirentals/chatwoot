/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

class Inboxes extends CacheEnabledApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'inbox';
  }

  getCampaigns(inboxId) {
    return axios.get(`${this.url}/${inboxId}/campaigns`);
  }

  deleteInboxAvatar(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/avatar`);
  }

  getAgentBot(inboxId) {
    return axios.get(`${this.url}/${inboxId}/agent_bot`);
  }

  setAgentBot(inboxId, botId) {
    return axios.post(`${this.url}/${inboxId}/set_agent_bot`, {
      agent_bot: botId,
    });
  }

  syncTemplates(inboxId) {
    return axios.post(`${this.url}/${inboxId}/sync_templates`);
  }

  getMessageTemplates(inboxId, params = {}, config = {}) {
    return axios.get(`${this.url}/${inboxId}/message_templates`, {
      ...config,
      params,
    });
  }

  updateWhatsappBusinessManagementToken(inboxId, businessManagementToken) {
    return axios.put(
      `${this.url}/${inboxId}/whatsapp_business_management_token`,
      {
        business_management_token: businessManagementToken,
      }
    );
  }

  createCSATTemplate(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template`, {
      template,
    });
  }

  getCSATTemplateStatus(inboxId) {
    return axios.get(`${this.url}/${inboxId}/csat_template`);
  }

  analyzeCSATTemplateUtility(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template/analyze`, {
      template,
    });
  }

  resetSecret(inboxId) {
    return axios.post(`${this.url}/${inboxId}/reset_secret`);
  }

  rotateHmacToken(inboxId) {
    return axios.post(`${this.url}/${inboxId}/rotate_hmac_token`);
  }

  enableWhatsappCalling(inboxId) {
    return axios.post(`${this.url}/${inboxId}/enable_whatsapp_calling`);
  }

  disableWhatsappCalling(inboxId) {
    return axios.post(`${this.url}/${inboxId}/disable_whatsapp_calling`);
  }

  setInboundCalls(inboxId, enabled) {
    return axios.post(`${this.url}/${inboxId}/set_inbound_calls`, {
      inbound_calls_enabled: enabled,
    });
  }

  // Modelos vivem na Meta, não no nosso banco: estas três mexem lá e sincronizam o espelho.
  createMessageTemplate(inboxId, template) {
    return axios.post(
      `${this.url}/${inboxId}/create_message_template`,
      template
    );
  }

  // A Meta não deixa trocar nome nem idioma de um modelo existente, só o conteúdo.
  updateMessageTemplate(inboxId, templateId, template) {
    return axios.post(`${this.url}/${inboxId}/update_message_template`, {
      ...template,
      template_id: templateId,
    });
  }

  destroyMessageTemplate(inboxId, { name, templateId }) {
    return axios.delete(`${this.url}/${inboxId}/destroy_message_template`, {
      params: { name, template_id: templateId },
    });
  }

  // Recado de voz: o que o cliente ouve quando a chamada é recusada. Vive na Meta, não no banco.
  getCallVoicemail(inboxId) {
    return axios.get(`${this.url}/${inboxId}/call_voicemail`);
  }

  // O áudio atual só sai da Meta com o token, então o servidor devolve os bytes. Tem que vir por
  // aqui, e não num `src` do <audio>: a requisição do elemento é do navegador, sem os cabeçalhos
  // de autenticação da API — e volta 401.
  getCallVoicemailAnnouncement(inboxId) {
    return axios.get(`${this.url}/${inboxId}/call_voicemail_announcement`, {
      responseType: 'blob',
    });
  }

  setCallVoicemail(inboxId, { file, triggers, timeoutSeconds }) {
    const formData = new FormData();
    formData.append('audio', file);
    formData.append('triggers', (triggers || ['REJECT']).join(','));
    if (timeoutSeconds) formData.append('timeout_seconds', timeoutSeconds);
    return axios.post(`${this.url}/${inboxId}/set_call_voicemail`, formData);
  }

  disableCallVoicemail(inboxId) {
    return axios.post(`${this.url}/${inboxId}/set_call_voicemail`, {
      disable: true,
    });
  }

  setCallRecording(inboxId, { recordingEnabled, transcriptionEnabled }) {
    return axios.post(`${this.url}/${inboxId}/set_call_recording`, {
      recording_enabled: recordingEnabled,
      transcription_enabled: transcriptionEnabled,
    });
  }
}

export default new Inboxes();
