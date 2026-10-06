<script setup>
import { ref, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import QRCode from 'qrcode';
import { useAlert } from 'dashboard/composables';
import BaileysAPI from 'dashboard/api/channel/baileys';
// Só `woot-wizard` é componente global; o resto se importa. Usar `woot-button` aqui fazia o botão
// de enviar sumir da tela, com "Failed to resolve component" no console.
import NextButton from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

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
const sessionId = ref('');
const qrDataUrl = ref('');
const numeroPareado = ref('');
const erro = ref('');
const salvando = ref(false);
let consulta = null;

// Só o nome: o número vem do próprio pareamento, então pedi-lo antes seria pedir ao usuário uma
// informação que a sessão já traz.
const v$ = useVuelidate({ inboxName: { required } }, { inboxName });

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
    const { data } = await BaileysAPI.obterSessao(sessionId.value);

    if (data.whatsapp_connection === 'connected') {
      pararConsulta();
      numeroPareado.value = data.whatsapp_number;
      etapa.value = ETAPAS.CONECTADO;
      return;
    }

    const { data: qr } = await BaileysAPI.obterQr(sessionId.value);
    if (qr.qr) await desenharQr(qr.qr);
  } catch (e) {
    // Um tropeço isolado (a ponte ainda gerando o QR, uma consulta perdida) não deve derrubar a
    // tela: a próxima consulta vem logo. Só registra.
    erro.value = e.response?.data?.error || '';
  }
};

const comecarPareamento = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  erro.value = '';
  salvando.value = true;

  try {
    const { data } = await BaileysAPI.abrirSessao();
    sessionId.value = data.id;
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
      session_id: sessionId.value,
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

const recomecar = () => {
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
    <Banner color="amber">
      {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.WARNING') }}
    </Banner>

    <form
      v-if="etapa === ETAPAS.NUMERO"
      class="flex flex-col gap-4"
      @submit.prevent="comecarPareamento"
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

      <p v-if="erro" class="text-sm text-n-ruby-11">{{ erro }}</p>

      <div class="flex gap-2">
        <NextButton
          type="submit"
          :label="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.START')"
          :is-loading="salvando"
        />
        <NextButton
          type="button"
          variant="ghost"
          :label="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.BACK')"
          @click="voltarParaProvedores"
        />
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
      <div v-else class="flex flex-col items-center gap-2 py-8">
        <Spinner />
        <span class="text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.WAITING_QR') }}
        </span>
      </div>

      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.WAITING_SCAN') }}
      </p>
      <NextButton
        type="button"
        variant="ghost"
        :label="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CHANGE_NUMBER')"
        @click="recomecar"
      />
    </div>

    <div v-else class="flex flex-col items-center gap-4 py-4">
      <span class="i-lucide-circle-check-big size-12 text-n-teal-11" />
      <p class="text-sm text-center text-n-slate-12">
        {{
          t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CONNECTED', {
            number: numeroPareado,
          })
        }}
      </p>
      <NextButton
        type="button"
        :label="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CREATE_INBOX')"
        :is-loading="salvando"
        @click="criarCaixa"
      />
    </div>
  </div>
</template>
