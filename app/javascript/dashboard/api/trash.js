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
}

export default new Trash();
