import { frontendURL } from '../../../../helper/URLHelper';

import SettingsContent from '../Wrapper.vue';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';
import Editor from './Editor.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/templates'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_templates',
          component: Index,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/templates'),
      component: SettingsContent,
      props: () => ({
        headerTitle: 'WHATSAPP_TEMPLATE_MGMT.TITLE',
        showBackButton: true,
      }),
      children: [
        {
          path: 'new',
          name: 'settings_templates_new',
          component: Editor,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: ':templateId/edit',
          name: 'settings_templates_edit',
          component: Editor,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
