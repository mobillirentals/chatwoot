<script setup>
import { computed } from 'vue';
import { previewText } from './composeTemplate';
import { renderMarkup } from './whatsappMarkup';

const props = defineProps({
  header: { type: String, default: '' },
  body: { type: String, default: '' },
  examples: { type: Object, default: () => ({}) },
  footer: { type: String, default: '' },
  buttons: { type: Array, default: () => [] },
});

// As variáveis viram exemplo: com `{{1}}` na tela ninguém consegue julgar se a mensagem ficou boa.
const cabecalho = computed(() => previewText(props.header));
const corpo = computed(() => previewText(props.body, props.examples));
// Só o corpo é formatado — a Meta entrega cabeçalho e rodapé como texto puro.
// renderMarkup escapa o HTML antes de marcar, então o v-html abaixo recebe só as tags dele.
const corpoHtml = computed(() => renderMarkup(corpo.value));
const rodape = computed(() => previewText(props.footer));

const comTexto = computed(() => props.buttons.filter(b => b.text?.trim()));

const agora = computed(() =>
  new Date().toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  })
);
</script>

<template>
  <!-- Fundo e balão imitam a conversa do WhatsApp de propósito: é assim que quem escreve consegue
       julgar o resultado sem precisar enviar para alguém. -->
  <div class="flex flex-col gap-2 p-4 rounded-xl bg-n-alpha-2">
    <div
      class="flex flex-col gap-1.5 px-3 py-2 rounded-lg rounded-tl-sm bg-n-background shadow-sm max-w-xs"
    >
      <p
        v-if="cabecalho"
        class="text-sm font-semibold break-words text-n-slate-12"
      >
        {{ cabecalho }}
      </p>

      <p
        v-if="corpo"
        class="text-sm break-words whitespace-pre-wrap text-n-slate-12"
        v-html="corpoHtml"
      />
      <p v-else class="text-sm break-words whitespace-pre-wrap text-n-slate-12">
        {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.PREVIEW.EMPTY_BODY') }}
      </p>

      <p v-if="rodape" class="text-xs break-words text-n-slate-10">
        {{ rodape }}
      </p>

      <span class="self-end text-[10px] tabular-nums text-n-slate-10">
        {{ agora }}
      </span>
    </div>

    <!-- No WhatsApp os botões ficam fora do balão, empilhados. -->
    <div v-if="comTexto.length" class="flex flex-col gap-1 max-w-xs">
      <span
        v-for="(botao, indice) in comTexto"
        :key="`${botao.type}-${indice}`"
        class="px-3 py-2 text-sm font-medium text-center truncate rounded-lg bg-n-background text-n-teal-11 shadow-sm"
      >
        {{ botao.text }}
      </span>
    </div>
  </div>
</template>
