/* global axios */

import ApiClient from './ApiClient';

class Trash extends ApiClient {
  constructor() {
    super('trash', { accountScoped: true });
  }

  get({ page }) {
    const url = page ? `${this.url}?page=${page}` : this.url;
    return axios.get(url);
  }

  restore(id) {
    return axios.post(`${this.url}/${id}/restore`);
  }

  messages(id, params = {}) {
    return axios.get(`${this.url}/${id}/messages`, { params });
  }
}

export default new Trash();
