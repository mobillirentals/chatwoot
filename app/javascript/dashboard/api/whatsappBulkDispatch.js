/* global axios */

import ApiClient from './ApiClient';

class WhatsappBulkDispatchAPI extends ApiClient {
  constructor() {
    super('whatsapp_bulk_dispatches', { accountScoped: true });
  }

  create({
    title,
    inboxId,
    templateName,
    templateLanguage,
    variableNames,
    file,
  }) {
    const formData = new FormData();
    formData.append('title', title);
    formData.append('inbox_id', inboxId);
    formData.append('template_name', templateName);
    formData.append('template_language', templateLanguage);
    variableNames.forEach(name => formData.append('variable_names[]', name));
    formData.append('file', file);

    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  updateMapping(id, columnMapping) {
    return axios.patch(`${this.url}/${id}`, { column_mapping: columnMapping });
  }

  confirm(id) {
    return axios.post(`${this.url}/${id}/confirm`);
  }
}

export default new WhatsappBulkDispatchAPI();
