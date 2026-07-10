import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import TrashHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/trash'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'trash_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'trash_list',
          meta: {
            permissions: ['administrator'],
          },
          component: TrashHome,
        },
      ],
    },
  ],
};
