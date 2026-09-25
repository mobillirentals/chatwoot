<script setup>
// Filtro dentro da conversa: procura por texto e por periodo sem precisar rolar o fio.
// Nasceu do historico importado, onde uma conversa chega a milhares de mensagens, mas serve
// para qualquer conversa longa da plataforma.
//
// De proposito NAO mexe na lista de mensagens da store: o fio da conversa e a tela que o time
// usa o dia todo, e filtrar por cima do estado dela traria risco sem necessidade. Aqui e uma
// consulta propria, que mostra os resultados ao lado.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import MessageApi from 'dashboard/api/inbox/message';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const selecionada = ref(null);
const texto = ref('');
const de = ref('');
const ate = ref('');
const resultados = ref([]);
const carregando = ref(false);
const buscou = ref(false);
const temMais = ref(false);
const erro = ref('');

const podeBuscar = computed(
  () =>
    Boolean(texto.value.trim() || de.value || ate.value) && !carregando.value
);

function corpo(mensagem) {
  if (mensagem.content) return mensagem.content;
  const anexos = mensagem.attachments || [];
  return anexos.length
    ? t('CONVERSATION.MESSAGE_FILTER.ATTACHMENT')
    : t('CONVERSATION.MESSAGE_FILTER.NO_CONTENT');
}

function quem(mensagem) {
  if (mensagem.message_type === 0) return mensagem.sender?.name || '';
  return (
    mensagem.sender?.name ||
    mensagem.additional_attributes?.agent_name ||
    t('CONVERSATION.MESSAGE_FILTER.TEAM')
  );
}

function quando(mensagem) {
  return messageTimestamp(mensagem.created_at, 'LLL d yyyy, h:mm a') || '';
}

async function buscar({ continuando = false } = {}) {
  if (carregando.value) return;
  carregando.value = true;
  erro.value = '';
  try {
    const { data } = await MessageApi.filtrar({
      conversationId: props.conversationId,
      q: texto.value.trim(),
      since: de.value,
      until: ate.value,
      before: continuando ? resultados.value[0]?.id : undefined,
    });
    const novos = data.payload || [];
    // a API devolve em ordem cronologica; "carregar mais" traz o que vem antes
    resultados.value = continuando ? [...novos, ...resultados.value] : novos;
    temMais.value = novos.length >= 50;
    buscou.value = true;
  } catch (e) {
    erro.value = t('CONVERSATION.MESSAGE_FILTER.ERROR');
  } finally {
    carregando.value = false;
  }
}

// Levar o resultado ate o fio usa o mecanismo que a busca global do Chatwoot ja usa: primeiro
// carregar a mensagem na conversa (fetchPreviousMessages com `after`), depois pedir o scroll.
// Sem a carga, a mensagem de 2023 nem existe no DOM e a tela pularia para o fim.
async function irPara(mensagem) {
  selecionada.value = mensagem.id;
  const carregadas = store.getters.getSelectedChat?.messages || [];
  const primeiraNaTela = carregadas[0]?.id;

  if (primeiraNaTela && mensagem.id < primeiraNaTela) {
    try {
      await store.dispatch('fetchPreviousMessages', {
        conversationId: props.conversationId,
        after: mensagem.id,
        before: primeiraNaTela,
      });
    } catch (e) {
      // se a carga falhar, o scroll abaixo cai no comportamento padrao do Chatwoot
    }
  }
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId: mensagem.id });

  // em tela estreita o painel cobre a conversa: manter aberto esconderia justamente a mensagem
  // que a pessoa acabou de escolher
  if (window.innerWidth < 1024) emit('close');
}

function limpar() {
  texto.value = '';
  de.value = '';
  ate.value = '';
  selecionada.value = null;
  resultados.value = [];
  buscou.value = false;
  temMais.value = false;
}

onMounted(() => {
  document.getElementById('filtro-mensagens-texto')?.focus();
});
</script>

<template>
  <!--
    Responsividade: em tela estreita o painel cobre a conversa (o contato tambem pode estar
    aberto, e tres colunas espremeriam tudo); a partir de lg ele vira coluna ao lado.
  -->
  <div
    class="absolute inset-y-0 z-20 flex flex-col w-full h-full min-w-0 border-l shadow-lg ltr:right-0 rtl:left-0 sm:max-w-sm lg:static lg:z-auto lg:w-80 lg:max-w-none lg:shadow-none xl:w-96 border-n-weak bg-n-solid-1"
  >
    <div
      class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
    >
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('CONVERSATION.MESSAGE_FILTER.TITLE') }}
      </h3>
      <Button
        icon="i-lucide-x"
        color="slate"
        variant="ghost"
        size="xs"
        @click="emit('close')"
      />
    </div>

    <form class="flex flex-col gap-3 px-4 py-3" @submit.prevent="buscar()">
      <Input
        id="filtro-mensagens-texto"
        v-model="texto"
        size="sm"
        :label="t('CONVERSATION.MESSAGE_FILTER.TEXT')"
        :placeholder="t('CONVERSATION.MESSAGE_FILTER.TEXT_PLACEHOLDER')"
      />
      <div class="flex gap-2">
        <Input
          v-model="de"
          type="date"
          size="sm"
          class="flex-1"
          :label="t('CONVERSATION.MESSAGE_FILTER.FROM')"
        />
        <Input
          v-model="ate"
          type="date"
          size="sm"
          class="flex-1"
          :label="t('CONVERSATION.MESSAGE_FILTER.TO')"
        />
      </div>
      <div class="flex gap-2">
        <Button
          type="submit"
          size="sm"
          :label="t('CONVERSATION.MESSAGE_FILTER.SEARCH')"
          :disabled="!podeBuscar"
          :is-loading="carregando"
        />
        <Button
          type="button"
          size="sm"
          variant="ghost"
          color="slate"
          :label="t('CONVERSATION.MESSAGE_FILTER.CLEAR')"
          @click="limpar"
        />
      </div>
    </form>

    <div class="flex-1 min-h-0 px-4 pb-4 overflow-y-auto">
      <p v-if="erro" class="py-2 text-sm text-n-ruby-11">{{ erro }}</p>

      <p
        v-else-if="buscou && !resultados.length && !carregando"
        class="py-2 text-sm text-n-slate-11"
      >
        {{ t('CONVERSATION.MESSAGE_FILTER.EMPTY') }}
      </p>

      <template v-else-if="resultados.length">
        <p class="py-2 text-xs text-n-slate-11">
          {{
            t('CONVERSATION.MESSAGE_FILTER.COUNT', { count: resultados.length })
          }}
        </p>
        <Button
          v-if="temMais"
          size="xs"
          variant="ghost"
          color="slate"
          class="w-full mb-2"
          :is-loading="carregando"
          :label="t('CONVERSATION.MESSAGE_FILTER.LOAD_MORE')"
          @click="buscar({ continuando: true })"
        />
        <ul class="flex flex-col gap-2">
          <li v-for="mensagem in resultados" :key="mensagem.id">
            <button
              type="button"
              class="w-full p-2 text-left rounded-lg bg-n-alpha-black2 dark:bg-n-solid-2 hover:bg-n-alpha-2 dark:hover:bg-n-solid-3"
              :class="{
                'outline outline-1 outline-n-brand':
                  selecionada === mensagem.id,
              }"
              @click="irPara(mensagem)"
            >
              <div class="flex items-baseline justify-between gap-2">
                <span class="text-xs font-medium truncate text-n-slate-12">
                  {{ quem(mensagem) }}
                </span>
                <span class="text-xs shrink-0 text-n-slate-10">
                  {{ quando(mensagem) }}
                </span>
              </div>
              <p
                class="mt-1 text-sm break-words whitespace-pre-line text-n-slate-11"
              >
                {{ corpo(mensagem) }}
              </p>
            </button>
          </li>
        </ul>
      </template>
    </div>
  </div>
</template>
