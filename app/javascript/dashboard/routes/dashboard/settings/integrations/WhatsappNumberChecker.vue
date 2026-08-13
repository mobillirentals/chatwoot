<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Integration from './Integration.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import IntegrationsAPI from 'dashboard/api/integrations';

const POLL_INTERVAL_MS = 2000;

const store = useStore();
const { t } = useI18n();

const integrationLoaded = ref(false);
const connectionStatus = ref('unavailable');
const connectedNumber = ref(null);
const qrImageUrl = ref('');
let pollTimer = null;

const integration = computed(() =>
  store.getters['integrations/getIntegration']('whatsapp_number_checker')
);

// Sem OAuth aqui — o "connect" e so o QR code aparecendo no slot #action; o unico link de
// acao real e o "disconnect" nativo, ja tratado pelo componente Integration.
const integrationAction = computed(() =>
  integration.value.enabled ? 'disconnect' : ''
);

const STATUS_I18N_KEYS = {
  connected: 'INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.STATUS.CONNECTED',
  waiting_qr: 'INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.STATUS.WAITING_QR',
  connecting: 'INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.STATUS.CONNECTING',
  disconnected:
    'INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.STATUS.DISCONNECTED',
  unavailable:
    'INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.STATUS.UNAVAILABLE',
};

const statusLabel = computed(() => {
  const key = STATUS_I18N_KEYS[connectionStatus.value];
  return key ? t(key) : connectionStatus.value;
});

const revokeQrUrl = () => {
  if (qrImageUrl.value) {
    URL.revokeObjectURL(qrImageUrl.value);
    qrImageUrl.value = '';
  }
};

const fetchQr = async () => {
  try {
    const response = await IntegrationsAPI.getWhatsappCheckerQr();
    // /qr pode responder 202/204 (ainda sem QR) com corpo que nao e imagem — so troca a
    // imagem exibida quando o content-type confirma que veio um PNG de verdade.
    if (!response.data.type?.includes('image')) return;

    revokeQrUrl();
    qrImageUrl.value = URL.createObjectURL(response.data);
  } catch (error) {
    // Servico fora do ar ou sem QR no momento — mantem sem imagem, tenta de novo no proximo poll.
  }
};

const refreshStatus = async () => {
  const status = await store.dispatch('integrations/getWhatsappCheckerStatus');
  if (!status) {
    connectionStatus.value = 'unavailable';
    return;
  }

  connectionStatus.value = status.whatsapp_connection;
  connectedNumber.value = status.connected_number;

  if (status.connected) {
    revokeQrUrl();
    await store.dispatch('integrations/get');
  } else {
    await fetchQr();
  }
};

const disconnect = async () => {
  try {
    await store.dispatch('integrations/disconnectWhatsappChecker');
    useAlert(
      t('INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.DISCONNECT_SUCCESS')
    );
    await refreshStatus();
  } catch (error) {
    useAlert(
      t('INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.DISCONNECT_ERROR')
    );
  }
};

onMounted(async () => {
  await store.dispatch('integrations/get');
  await refreshStatus();
  integrationLoaded.value = true;
  pollTimer = setInterval(refreshStatus, POLL_INTERVAL_MS);
});

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer);
  revokeQrUrl();
});
</script>

<template>
  <SettingsLayout :is-loading="!integrationLoaded">
    <template #header>
      <BaseSettingsHeader
        :title="$t('INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.HEADER')"
        description=""
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div class="space-y-5">
        <Integration
          :integration-id="integration.id"
          :integration-logo="integration.logo"
          :integration-name="integration.name"
          :integration-description="integration.description"
          :integration-enabled="integration.enabled"
          :integration-action="integrationAction"
          use-custom-delete
          :delete-confirmation-text="{
            title: t(
              'INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.DELETE.TITLE'
            ),
            message: t(
              'INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.DELETE.MESSAGE'
            ),
          }"
          @delete="disconnect"
        >
          <template #action>
            <div class="flex flex-col items-center gap-2">
              <img
                v-if="qrImageUrl"
                :src="qrImageUrl"
                class="w-40 h-40 rounded-md border border-n-weak"
                alt="QR code"
              />
              <p class="text-n-slate-11 text-body-main">{{ statusLabel }}</p>
            </div>
          </template>
        </Integration>
        <div
          v-if="integration.enabled"
          class="p-4 outline outline-n-container outline-1 bg-n-card rounded-xl"
        >
          <p class="text-n-slate-11 text-body-main">
            {{
              t('INTEGRATION_SETTINGS.WHATSAPP_NUMBER_CHECKER.CONNECTED_AS', {
                number: connectedNumber,
              })
            }}
          </p>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
