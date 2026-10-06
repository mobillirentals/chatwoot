<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';
import BaileysAPI from 'dashboard/api/channel/baileys';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();

// O QR do WhatsApp expira em poucos segundos e a sessão gera outro sozinha, então a tela pergunta
// de tempos em tempos em vez de mostrar um código que morre na mão de quem está com o celular.
const INTERVALO_DE_CONSULTA = 2000;

const conexao = ref('');
const numeroPareado = ref('');
const numeroErrado = ref(null);
const qrDataUrl = ref('');
const reconectando = ref(false);
const erro = ref('');
let consulta = null;

// Enquanto está pareada não há o que mostrar além do estado; o QR só aparece durante o reparo.
const pareada = computed(() => conexao.value === 'connected');
const aguardandoLeitura = computed(() =>
  ['waiting_qr', 'connecting', 'disconnected'].includes(conexao.value)
);

const pararConsulta = () => {
  if (consulta) clearInterval(consulta);
  consulta = null;
};

onBeforeUnmount(pararConsulta);

const consultarEstado = async () => {
  try {
    const { data } = await BaileysAPI.estadoDaCaixa(props.inbox.id);
    conexao.value = data.whatsapp_connection;
    numeroPareado.value = data.whatsapp_number || '';
    numeroErrado.value = data.wrong_number || null;

    if (pareada.value) {
      pararConsulta();
      qrDataUrl.value = '';
      return;
    }

    const { data: qr } = await BaileysAPI.qrDaCaixa(props.inbox.id);
    if (qr.qr)
      qrDataUrl.value = await QRCode.toDataURL(qr.qr, {
        width: 280,
        margin: 1,
      });
  } catch (e) {
    // Uma consulta perdida não deve derrubar a tela: a próxima vem logo.
    erro.value = e.response?.data?.error || '';
  }
};

onMounted(consultarEstado);

const reconectar = async () => {
  erro.value = '';
  reconectando.value = true;

  try {
    await BaileysAPI.reconectarCaixa(props.inbox.id);
    await consultarEstado();
    pararConsulta();
    consulta = setInterval(consultarEstado, INTERVALO_DE_CONSULTA);
  } catch (e) {
    erro.value =
      e.response?.data?.error ||
      t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.BRIDGE_ERROR');
  } finally {
    reconectando.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex items-center gap-2">
      <span
        class="rounded-full size-2"
        :class="pareada ? 'bg-n-teal-9' : 'bg-n-amber-9'"
      />
      <span class="text-sm text-n-slate-12">
        {{
          pareada
            ? t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS.CONNECTED', {
                number: numeroPareado,
              })
            : t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS.DISCONNECTED')
        }}
      </span>
    </div>

    <!-- Parear outro número faria a caixa seguir com o histórico e os contatos do antigo, mas
         enviando de outro lugar: o cliente receberia resposta de um número que nunca contatou. -->
    <Banner v-if="numeroErrado" color="ruby">
      {{
        t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS.WRONG_NUMBER', {
          scanned: numeroErrado.pareado,
          expected: numeroErrado.esperado,
        })
      }}
    </Banner>

    <div
      v-if="aguardandoLeitura && qrDataUrl"
      class="flex flex-col items-start gap-2"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS.SCAN_INSTRUCTIONS') }}
      </p>
      <!-- fundo branco fixo: o leitor do WhatsApp precisa do contraste, e no tema escuro o QR
           ficaria sobre fundo escuro -->
      <div class="p-3 bg-white rounded-xl">
        <img
          :src="qrDataUrl"
          :alt="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.QR_ALT')"
          width="280"
          height="280"
        />
      </div>
    </div>

    <p v-if="erro" class="text-sm text-n-ruby-11">{{ erro }}</p>

    <div>
      <NextButton
        type="button"
        :variant="pareada ? 'faded' : 'solid'"
        :label="t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS.RECONNECT')"
        :is-loading="reconectando"
        @click="reconectar"
      />
      <p class="mt-2 text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS.RECONNECT_HELP') }}
      </p>
    </div>
  </div>
</template>
