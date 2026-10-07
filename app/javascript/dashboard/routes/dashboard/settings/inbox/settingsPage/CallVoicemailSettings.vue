<script setup>
import { computed, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
  // O gatilho é REJECT: com as chamadas de entrada ligadas, o recado existe mas nunca toca.
  // Avisar isso evita alguém configurar e achar que está quebrado.
  inboundCallsEnabled: { type: Boolean, default: false },
});

const { t } = useI18n();

const carregando = ref(true);
const salvando = ref(false);
const config = ref({});
const seletor = useTemplateRef('seletor');
const tocador = useTemplateRef('tocador');

const ativo = computed(() => config.value?.status === 'ENABLED');
const gatilhos = computed(() => config.value?.triggers || []);

// A URL volta com um carimbo de tempo para o navegador não servir o áudio antigo do cache depois
// de uma troca — sem isso, quem acabou de subir um recado novo ouve o anterior e acha que falhou.
const audioUrl = ref('');
const atualizarAudio = () => {
  audioUrl.value = ativo.value
    ? `${InboxesAPI.callVoicemailAnnouncementUrl(props.inbox.id)}?t=${Date.now()}`
    : '';
  if (tocador.value) tocador.value.load();
};

const carregar = async () => {
  carregando.value = true;
  try {
    const { data } = await InboxesAPI.getCallVoicemail(props.inbox.id);
    config.value = data || {};
    atualizarAudio();
  } catch (e) {
    config.value = {};
  } finally {
    carregando.value = false;
  }
};

onMounted(carregar);

const escolherArquivo = () => seletor.value?.click();

const aoEscolher = async evento => {
  const file = evento.target.files?.[0];
  evento.target.value = '';
  if (!file) return;

  salvando.value = true;
  try {
    const { data } = await InboxesAPI.setCallVoicemail(props.inbox.id, {
      file,
      triggers: gatilhos.value.length ? gatilhos.value : ['REJECT'],
    });
    config.value = data || {};
    atualizarAudio();
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (e) {
    useAlert(
      e?.response?.data?.message || t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
    );
  } finally {
    salvando.value = false;
  }
};

const desligar = async () => {
  salvando.value = true;
  try {
    const { data } = await InboxesAPI.disableCallVoicemail(props.inbox.id);
    config.value = data || {};
    atualizarAudio();
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (e) {
    useAlert(
      e?.response?.data?.message || t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
    );
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex items-center justify-between gap-3">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('INBOX_MGMT.WHATSAPP_CALLING.VOICEMAIL.LABEL') }}
      </span>
      <span
        v-if="!carregando"
        class="flex items-center gap-1.5 text-xs shrink-0"
        :class="ativo ? 'text-n-teal-11' : 'text-n-slate-11'"
      >
        <span
          class="rounded-full size-1.5"
          :class="ativo ? 'bg-n-teal-9' : 'bg-n-slate-9'"
        />
        {{
          ativo
            ? $t('INBOX_MGMT.WHATSAPP_CALLING.VOICEMAIL.ACTIVE')
            : $t('INBOX_MGMT.WHATSAPP_CALLING.VOICEMAIL.INACTIVE')
        }}
      </span>
    </div>

    <p v-if="carregando" class="text-sm text-n-slate-11">
      {{ $t('INBOX_MGMT.WHATSAPP_CALLING.VOICEMAIL.LOADING') }}
    </p>

    <template v-else>
      <!-- Ouvir o que está no ar hoje, antes de trocar. -->
      <audio
        v-if="ativo && audioUrl"
        ref="tocador"
        controls
        class="w-full max-w-sm h-9"
        preload="none"
      >
        <source :src="audioUrl" type="audio/ogg" />
      </audio>

      <div class="flex flex-wrap items-center gap-2">
        <input
          ref="seletor"
          type="file"
          accept="audio/ogg,.ogg,.opus"
          class="hidden"
          @change="aoEscolher"
        />
        <NextButton
          type="button"
          size="sm"
          :label="
            ativo
              ? $t('INBOX_MGMT.WHATSAPP_CALLING.VOICEMAIL.REPLACE')
              : $t('INBOX_MGMT.WHATSAPP_CALLING.VOICEMAIL.UPLOAD')
          "
          :is-loading="salvando"
          @click="escolherArquivo"
        />
        <NextButton
          v-if="ativo"
          type="button"
          size="sm"
          variant="faded"
          :label="$t('INBOX_MGMT.WHATSAPP_CALLING.VOICEMAIL.DISABLE')"
          :disabled="salvando"
          @click="desligar"
        />
      </div>

      <p v-if="ativo && inboundCallsEnabled" class="text-xs text-n-amber-11">
        {{ $t('INBOX_MGMT.WHATSAPP_CALLING.VOICEMAIL.WONT_PLAY') }}
      </p>

      <p class="text-xs text-n-slate-11">
        {{ $t('INBOX_MGMT.WHATSAPP_CALLING.VOICEMAIL.HELP_TEXT') }}
      </p>
    </template>
  </div>
</template>
