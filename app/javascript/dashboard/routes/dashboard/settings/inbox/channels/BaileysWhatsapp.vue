<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import QRCode from 'qrcode';
import { useAlert } from 'dashboard/composables';
import BaileysAPI from 'dashboard/api/channel/baileys';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

// O QR do WhatsApp expira em poucos segundos e a sessão gera um novo sozinha, então a tela
// pergunta de tempos em tempos em vez de mostrar um código que morre na mão do usuário.
const INTERVALO_DE_CONSULTA = 2000;

const ETAPAS = {
  NUMERO: 'numero',
  PAREANDO: 'pareando',
  CONECTADO: 'conectado',
};

const etapa = ref(ETAPAS.NUMERO);
const inboxName = ref('');
const phoneNumber = ref('');
const qrDataUrl = ref('');
const numeroPareado = ref('');
const erro = ref('');
const salvando = ref(false);
let consulta = null;

const regras = {
  inboxName: { required },
  // O número precisa do DDI porque é ele que identifica a sessão na ponte.
  phoneNumber: {
    required,
    comDdi: valor =>
      /^\+?[1-9]\d{10,14}$/.test(String(valor).replace(/[\s()-]/g, '')),
  },
};
const v$ = useVuelidate(regras, { inboxName, phoneNumber });

const soDigitos = computed(() => phoneNumber.value.replace(/\D/g, ''));

const pararConsulta = () => {
  if (consulta) clearInterval(consulta);
  consulta = null;
};

onBeforeUnmount(pararConsulta);

const desenharQr = async texto => {
  qrDataUrl.value = await QRCode.toDataURL(texto, { width: 320, margin: 1 });
};

const consultarSessao = async () => {
  try {
    const { data } = await BaileysAPI.obterSessao(soDigitos.value);

    if (data.whatsapp_connection === 'connected') {
      pararConsulta();
      numeroPareado.value = data.whatsapp_number;
      etapa.value = ETAPAS.CONECTADO;
      return;
    }

    const { data: qr } = await BaileysAPI.obterQr(soDigitos.value);
    if (qr.qr) await desenharQr(qr.qr);
  } catch (e) {
    // Um tropeço isolado (a ponte ainda gerando o QR, uma consulta perdida) não deve derrubar a
    // tela: a próxima consulta vem logo. Só registra.
    erro.value = e.response?.data?.error || '';
  }
};

const começarPareamento = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  erro.value = '';
  salvando.value = true;

  try {
    await BaileysAPI.abrirSessao(soDigitos.value);
    etapa.value = ETAPAS.PAREANDO;
    await consultarSessao();
    consulta = setInterval(consultarSessao, INTERVALO_DE_CONSULTA);
  } catch (e) {
    erro.value =
      e.response?.data?.error ||
      t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.BRIDGE_ERROR');
  } finally {
    salvando.value = false;
  }
};

const criarCaixa = async () => {
  salvando.value = true;

  try {
    const { data } = await BaileysAPI.criarCaixa({
      phone_number: soDigitos.value,
      name: inboxName.value.trim(),
    });

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: data.id },
    });
  } catch (e) {
    useAlert(
      e.response?.data?.error || t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE')
    );
  } finally {
    salvando.value = false;
  }
};

const recomeçar = () => {
  pararConsulta();
  qrDataUrl.value = '';
  etapa.value = ETAPAS.NUMERO;
};

const voltarParaProvedores = () => {
  router.push({ name: route.name, params: route.params, query: {} });
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <woot-banner
      color-scheme="alert"
      :banner-message="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.WARNING')"
      class="rounded-lg"
    />

    <form
      v-if="etapa === ETAPAS.NUMERO"
      class="flex flex-col gap-4"
      @submit.prevent="começarPareamento;"
    >
      <label :class="{ error: v$.inboxName.$error }">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :placeholder="t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>

      <label :class="{ error: v$.phoneNumber.$error }">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="text"
          :placeholder="t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>

      <p v-if="erro" class="text-sm text-n-ruby-11">{{ erro }}</p>

      <div class="flex gap-2">
        <woot-submit-button
          :loading="salvando"
          :button-text="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.START')"
        />
        <woot-button variant="clear" @click.prevent="voltarParaProvedores">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.BACK') }}
        </woot-button>
      </div>
    </form>

    <div
      v-else-if="etapa === ETAPAS.PAREANDO"
      class="flex flex-col items-center gap-4 py-4"
    >
      <p class="max-w-md text-sm text-center text-n-slate-11">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.SCAN_INSTRUCTIONS') }}
      </p>

      <!-- fundo branco fixo: o leitor do WhatsApp precisa do contraste, e no tema escuro o QR
           ficaria sobre fundo escuro -->
      <div v-if="qrDataUrl" class="p-3 bg-white rounded-xl">
        <img
          :src="qrDataUrl"
          :alt="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.QR_ALT')"
          width="320"
          height="320"
        />
      </div>
      <woot-loading-state
        v-else
        :message="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.WAITING_QR')"
      />

      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.WAITING_SCAN') }}
      </p>
      <woot-button variant="clear" @click="recomeçar;">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CHANGE_NUMBER') }}
      </woot-button>
    </div>

    <div v-else class="flex flex-col items-center gap-4 py-4">
      <fluent-icon icon="checkmark-circle" size="48" class="text-n-teal-11" />
      <p class="text-sm text-center text-n-slate-12">
        {{
          t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CONNECTED', {
            number: numeroPareado,
          })
        }}
      </p>
      <woot-submit-button
        :loading="salvando"
        :button-text="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CREATE_INBOX')"
        @click="criarCaixa"
      />
    </div>
  </div>
</template>
