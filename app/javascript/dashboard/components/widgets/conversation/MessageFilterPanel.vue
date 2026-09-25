<script setup>
// Pesquisa dentro da conversa, em dois modos que nao se misturam:
//
// - Texto: lista os resultados e clicar leva ate a mensagem no fio (mesmo mecanismo da busca
//   global do Chatwoot: carregar a mensagem e pedir o scroll).
// - Periodo: NAO devolve lista. O proprio fio passa a mostrar so o intervalo pedido, com um
//   aviso no topo da conversa. Foi pedido assim porque lista lateral para "ver junho" nao parece
//   nativo: a pessoa quer ler a conversa daquele mes, nao um relatorio dela.
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
  periodoAtivo: { type: Object, default: null },
});
const emit = defineEmits(['close', 'aplicarPeriodo']);

const { t } = useI18n();
const store = useStore();

const modo = ref('texto');
const texto = ref('');
const de = ref(props.periodoAtivo?.de || '');
const ate = ref(props.periodoAtivo?.ate || '');
const selecionada = ref(null);
const resultados = ref([]);
const carregando = ref(false);
const buscou = ref(false);
const temMais = ref(false);
const erro = ref('');

const podePesquisar = computed(
  () => Boolean(texto.value.trim()) && !carregando.value
);
const podeAplicar = computed(() => Boolean(de.value || ate.value));

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

async function pesquisar({ continuando = false } = {}) {
  if (carregando.value) return;
  carregando.value = true;
  erro.value = '';
  try {
    const { data } = await MessageApi.filtrar({
      conversationId: props.conversationId,
      q: texto.value.trim(),
      before: continuando ? resultados.value[0]?.id : undefined,
    });
    const novos = data.payload || [];
    // a API devolve em ordem cronologica; "mais antigos" entra na frente
    resultados.value = continuando ? [...novos, ...resultados.value] : novos;
    temMais.value = novos.length >= 50;
    buscou.value = true;
  } catch (e) {
    erro.value = t('CONVERSATION.MESSAGE_FILTER.ERROR');
  } finally {
    carregando.value = false;
  }
}

// Levar o resultado ate o fio: primeiro carregar a mensagem na conversa, depois pedir o scroll.
// Sem a carga, uma mensagem de 2023 nem existe no DOM e a tela pularia para o fim.
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
      // se a carga falhar, o scroll cai no comportamento padrao do Chatwoot
    }
  }
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId: mensagem.id });

  // em tela estreita (abaixo de md, como o painel nativo) o painel cobre a conversa: manter
  // aberto esconderia justamente a mensagem escolhida
  if (window.innerWidth < 768) emit('close');
}

function aplicarPeriodo() {
  if (!podeAplicar.value) return;
  // o fio assume o filtro e mostra o aviso; o painel sai da frente
  emit('aplicarPeriodo', { de: de.value, ate: ate.value });
  emit('close');
}

function limpar() {
  if (modo.value === 'texto') {
    texto.value = '';
    resultados.value = [];
    selecionada.value = null;
    buscou.value = false;
    temMais.value = false;
    return;
  }
  de.value = '';
  ate.value = '';
  emit('aplicarPeriodo', null);
}

function trocarModo(novo) {
  modo.value = novo;
  erro.value = '';
}

onMounted(() => {
  document.getElementById('filtro-mensagens-texto')?.focus();
});
</script>

<template>
  <!--
    Mesmas classes de layout do painel de Contato (ConversationSidebar): em tela estreita cobre a
    conversa, de `md` para cima vira coluna ao lado, com a mesma largura. Copiar o nativo em vez
    de inventar medida e o que faz o painel nao parecer enxertado.
  -->
  <div
    class="fixed top-0 z-40 flex flex-col w-full h-full max-w-sm overflow-hidden shadow-lg bg-n-surface-2 ltr:right-0 rtl:left-0 ltr:border-l rtl:border-r border-n-weak md:static md:w-[320px] md:min-w-[320px] md:shadow-none 2xl:w-[360px] 2xl:min-w-[360px]"
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

    <div class="flex gap-1 px-4 pt-3">
      <Button
        size="xs"
        :variant="modo === 'texto' ? 'solid' : 'ghost'"
        :color="modo === 'texto' ? 'blue' : 'slate'"
        :label="t('CONVERSATION.MESSAGE_FILTER.MODE_TEXT')"
        @click="trocarModo('texto')"
      />
      <Button
        size="xs"
        :variant="modo === 'periodo' ? 'solid' : 'ghost'"
        :color="modo === 'periodo' ? 'blue' : 'slate'"
        :label="t('CONVERSATION.MESSAGE_FILTER.MODE_PERIOD')"
        @click="trocarModo('periodo')"
      />
    </div>

    <form
      v-if="modo === 'texto'"
      class="flex flex-col gap-3 px-4 py-3"
      @submit.prevent="pesquisar()"
    >
      <Input
        id="filtro-mensagens-texto"
        v-model="texto"
        size="sm"
        :placeholder="t('CONVERSATION.MESSAGE_FILTER.TEXT_PLACEHOLDER')"
      />
      <div class="flex gap-2">
        <Button
          type="submit"
          size="sm"
          :label="t('CONVERSATION.MESSAGE_FILTER.SEARCH')"
          :disabled="!podePesquisar"
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

    <form
      v-else
      class="flex flex-col gap-3 px-4 py-3"
      @submit.prevent="aplicarPeriodo"
    >
      <p class="text-xs text-n-slate-11">
        {{ t('CONVERSATION.MESSAGE_FILTER.PERIOD_HINT') }}
      </p>
      <div class="flex flex-col gap-2 sm:flex-row">
        <Input
          v-model="de"
          type="date"
          size="sm"
          class="flex-1 min-w-0"
          :label="t('CONVERSATION.MESSAGE_FILTER.FROM')"
        />
        <Input
          v-model="ate"
          type="date"
          size="sm"
          class="flex-1 min-w-0"
          :label="t('CONVERSATION.MESSAGE_FILTER.TO')"
        />
      </div>
      <div class="flex gap-2">
        <Button
          type="submit"
          size="sm"
          :label="t('CONVERSATION.MESSAGE_FILTER.APPLY')"
          :disabled="!podeAplicar"
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

    <div
      v-if="modo === 'texto'"
      class="flex-1 min-h-0 px-4 pb-4 overflow-y-auto"
    >
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
          @click="pesquisar({ continuando: true })"
        />
        <!-- list-none: sem isso o estilo base do projeto desenha a bolinha do marcador -->
        <ul class="flex flex-col gap-2 list-none">
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
