<script setup>
import { computed, onMounted, reactive, ref, useTemplateRef, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TemplateBubblePreview from './TemplateBubblePreview.vue';
import {
  CATEGORIES,
  LIMITS,
  findVariables,
  fromComponents,
  insertVariable,
  slugifyName,
  syncExamples,
  unsupportedReason,
  validateTemplate,
} from './composeTemplate';
import { MARKS, wrapSelection } from './whatsappMarkup';

// A Meta formata só o corpo: no cabeçalho e no rodapé o asterisco chegaria literal ao cliente.
const FORMATOS = [
  { chave: 'BOLD', marcador: MARKS.BOLD, icone: 'i-lucide-bold' },
  { chave: 'ITALIC', marcador: MARKS.ITALIC, icone: 'i-lucide-italic' },
  { chave: 'STRIKE', marcador: MARKS.STRIKE, icone: 'i-lucide-strikethrough' },
  { chave: 'MONO', marcador: MARKS.MONO, icone: 'i-lucide-code' },
];

const META_MANAGER =
  'https://business.facebook.com/latest/whatsapp_manager/message_templates';

const IDIOMAS = [
  { value: 'pt_BR', label: 'Português (Brasil)' },
  { value: 'en_US', label: 'English (US)' },
  { value: 'es', label: 'Español' },
];

// Um visual só para todo campo: definido aqui porque repetir a lista de classes em cada input é
// como eles acabam divergindo entre si.
const CAMPO =
  'w-full px-3 py-2 text-sm transition-colors border rounded-lg outline-none bg-n-alpha-black2 border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-brand disabled:cursor-not-allowed disabled:text-n-slate-10';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');

// O modelo vive na Meta, numa conta comercial do WhatsApp Cloud. Twilio e 360dialog não alcançam
// essa API, então não aparecem aqui.
const caixasElegiveis = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::Whatsapp' &&
      inbox.provider_config?.business_account_id
  )
);

const opcoesDeCaixa = computed(() =>
  caixasElegiveis.value.map(caixa => ({ value: caixa.id, label: caixa.name }))
);

const templateId = computed(() => route.params.templateId || null);
const editando = computed(() => Boolean(templateId.value));

const etapa = ref(1);
const carregando = ref(false);
const salvando = ref(false);
const bloqueio = ref(null);
// String vazia em vez de null porque é o que o ComboBox espera quando nada foi escolhido.
const inboxId = ref(Number(route.query.inbox_id) || '');
const corpoRef = useTemplateRef('corpoRef');

const modelo = ref({
  name: '',
  language: 'pt_BR',
  category: 'UTILITY',
  header: '',
  body: '',
  examples: {},
  footer: '',
  buttons: [],
});

const variaveis = computed(() => findVariables(modelo.value.body));

// Montado aqui porque as chaves duplas no template seriam lidas como interpolação do Vue.
const rotuloVariavel = numero => `{{${numero}}}`;

// Um campo de exemplo por variável, criado e removido junto com ela. O que já foi escrito fica.
watch(
  () => modelo.value.body,
  body => {
    modelo.value.examples = syncExamples(body, modelo.value.examples);
  }
);

const erros = computed(() =>
  validateTemplate(modelo.value, { editing: editando.value })
);

const valido = computed(
  () => Object.keys(erros.value).length === 0 && Boolean(inboxId.value)
);

// Um formulário em branco não é um formulário errado. O erro só aparece depois que a pessoa mexeu
// no campo ou tentou enviar — senão a tela abre inteira vermelha antes de ela escrever nada.
const tocados = reactive({});
const tentouEnviar = ref(false);
const marcarTocado = campo => {
  tocados[campo] = true;
};
const erroDe = campo =>
  tocados[campo] || tentouEnviar.value ? erros.value[campo] : null;

const contagem = campo =>
  `${(modelo.value[campo] || '').length}/${LIMITS[campo]}`;

const adicionarBotao = tipo => {
  if (modelo.value.buttons.length >= LIMITS.buttons) return;
  modelo.value.buttons.push({ type: tipo, text: '', url: '' });
};

const removerBotao = indice => modelo.value.buttons.splice(indice, 1);

// A Meta normaliza o nome sozinha no painel dela. Normalizar enquanto digita, em vez de reclamar
// depois, poupa a pessoa de descobrir a regra por tentativa e erro.
const aoDigitarNome = evento => {
  modelo.value.name = slugifyName(evento.target.value);
  evento.target.value = modelo.value.name;
};

// Inserir no cursor em vez de deixar digitar a chave: a numeração precisa ser sequencial a partir
// de 1, e escrever {{2}} antes do {{1}} faz a Meta recusar o modelo inteiro.
const inserirVariavel = () => {
  const campo = corpoRef.value;
  const posicao = campo?.selectionStart ?? modelo.value.body.length;
  const { texto, cursor } = insertVariable(modelo.value.body, posicao);
  modelo.value.body = texto;

  requestAnimationFrame(() => {
    campo?.focus();
    campo?.setSelectionRange(cursor, cursor);
  });
};

// Os botões usam @mousedown.prevent para o textarea não perder o foco — sem isso a seleção some
// antes do clique chegar aqui e a marcação cairia no lugar errado.
const formatar = marcador => {
  const campo = corpoRef.value;
  if (!campo) return;

  const resultado = wrapSelection(
    modelo.value.body,
    campo.selectionStart,
    campo.selectionEnd,
    marcador
  );
  modelo.value.body = resultado.texto;

  requestAnimationFrame(() => {
    campo.focus();
    campo.setSelectionRange(resultado.inicio, resultado.fim);
  });
};

const voltarParaLista = () => router.push({ name: 'settings_templates' });

// Editar reenvia o modelo inteiro para a Meta. Carregar o que está lá hoje — e recusar o que esta
// tela não sabe remontar — é o que evita apagar um cabeçalho de imagem sem ninguém perceber.
const carregarModelo = async () => {
  carregando.value = true;
  try {
    const { data } = await InboxesAPI.getMessageTemplates(inboxId.value);
    const existente = (data.payload || []).find(
      item => String(item.id) === String(templateId.value)
    );

    if (!existente) {
      bloqueio.value = 'NOT_FOUND';
      return;
    }

    bloqueio.value = unsupportedReason(existente);
    modelo.value = fromComponents(existente);
  } catch {
    bloqueio.value = 'NOT_FOUND';
  } finally {
    carregando.value = false;
  }
};

const salvar = async () => {
  // Botão vivo mesmo com o formulário incompleto: clicar e ver o que falta ensina mais do que um
  // botão apagado sem explicação.
  tentouEnviar.value = true;
  if (!valido.value) return;

  salvando.value = true;
  try {
    if (editando.value) {
      // A Meta não aceita trocar a categoria de um modelo aprovado, então ela nem vai no corpo:
      // mandar a mesma de volta só cria uma chance de recusa sem ganho nenhum.
      const { category, ...conteudo } = modelo.value;
      await InboxesAPI.updateMessageTemplate(
        inboxId.value,
        templateId.value,
        conteudo
      );
    } else {
      await InboxesAPI.createMessageTemplate(inboxId.value, modelo.value);
    }
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.EDITOR.SUBMITTED'));
    voltarParaLista();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('WHATSAPP_TEMPLATE_MGMT.EDITOR.FAILED')
    );
  } finally {
    salvando.value = false;
  }
};

onMounted(async () => {
  await store.dispatch('inboxes/get');

  if (!inboxId.value && caixasElegiveis.value.length === 1) {
    inboxId.value = caixasElegiveis.value[0].id;
  }

  if (!editando.value) return;

  etapa.value = 2;
  if (inboxId.value) await carregarModelo();
  else bloqueio.value = 'NOT_FOUND';
});
</script>

<template>
  <!-- O wrapper de configurações entrega altura fixa e `overflow-hidden`, então a rolagem tem que
       ser deste container: sem isso o formulário fica cortado no rodapé. -->
  <div class="flex flex-col flex-1 w-full min-h-0 overflow-y-auto">
    <div
      v-if="carregando"
      class="flex items-center justify-center gap-2 p-10 text-sm text-n-slate-11"
    >
      <Icon icon="i-lucide-loader-circle" class="size-4 animate-spin" />
      {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.LOADING') }}
    </div>

    <!-- O bloqueio aparece em vez do formulário: deixar editar e apagar conteúdo no caminho é pior
         do que mandar a pessoa para o painel da Meta. -->
    <div
      v-else-if="bloqueio"
      class="w-full max-w-2xl px-6 py-10 mx-auto text-center"
    >
      <div
        class="flex items-center justify-center mx-auto rounded-full size-10 bg-n-amber-3"
      >
        <Icon icon="i-lucide-lock" class="size-5 text-n-amber-11" />
      </div>
      <h2 class="mt-4 text-base font-medium text-n-slate-12">
        {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.UNSUPPORTED.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ $t(`WHATSAPP_TEMPLATE_MGMT.EDITOR.UNSUPPORTED.${bloqueio}`) }}
      </p>
      <div class="flex justify-center gap-2 mt-5">
        <Button
          :label="$t('WHATSAPP_TEMPLATE_MGMT.EDITOR.BACK_TO_LIST')"
          color="slate"
          size="sm"
          @click="voltarParaLista"
        />
        <Button
          :label="$t('WHATSAPP_TEMPLATE_MGMT.EDITOR.UNSUPPORTED.OPEN_META')"
          icon="i-lucide-external-link"
          size="sm"
          trailing-icon
          :href="META_MANAGER"
          target="_blank"
          rel="noopener noreferrer"
        />
      </div>
    </div>

    <div
      v-else-if="!caixasElegiveis.length"
      class="w-full max-w-2xl px-6 py-10 mx-auto text-sm text-center text-n-slate-11"
    >
      {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.NO_INBOX') }}
    </div>

    <template v-else>
      <!-- Sem `flex-1`: com ele o rodapé era empurrado para o fundo da tela mesmo quando o passo
           é curto, deixando um vão grande no meio. Largura casada com o cabeçalho da página. -->
      <div class="w-full max-w-7xl px-6 pt-5 pb-8 mx-auto">
        <!-- A Meta mostra em que passo você está; sem isso "Próximo" parece um salto no escuro. -->
        <div v-if="!editando" class="flex items-center gap-1.5 mb-5 text-xs">
          <template v-for="(passo, indice) in [1, 2]" :key="passo">
            <span
              v-if="indice"
              class="w-6 h-px"
              :class="etapa === 2 ? 'bg-n-brand' : 'bg-n-strong'"
            />
            <button
              type="button"
              class="flex items-center gap-1.5 px-2.5 py-1 transition-colors border rounded-full cursor-pointer"
              :class="
                etapa === passo
                  ? 'border-n-brand text-n-brand bg-n-brand/10 font-medium'
                  : 'border-n-weak text-n-slate-11 bg-transparent hover:text-n-slate-12'
              "
              @click="etapa = passo"
            >
              <span
                class="flex items-center justify-center text-[10px] rounded-full size-4 tabular-nums"
                :class="
                  etapa === passo
                    ? 'bg-n-brand text-white'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                {{ passo }}
              </span>
              {{ $t(`WHATSAPP_TEMPLATE_MGMT.EDITOR.STEPS.${passo}`) }}
            </button>
          </template>
        </div>

        <div class="flex items-start gap-6">
          <div class="flex flex-col flex-1 gap-4 min-w-0">
            <!-- Passo 1: categoria. A Meta pergunta primeiro porque muda preço e regra de envio. -->
            <template v-if="etapa === 1">
              <section
                class="flex flex-col gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1"
              >
                <div class="flex flex-col gap-1">
                  <h2 class="text-sm font-medium text-n-slate-12">
                    {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.CATEGORY.TITLE') }}
                  </h2>
                  <p class="text-sm text-n-slate-11">
                    {{
                      $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.CATEGORY.DESCRIPTION')
                    }}
                  </p>
                </div>

                <div class="grid gap-3 sm:grid-cols-2">
                  <button
                    v-for="categoria in CATEGORIES"
                    :key="categoria"
                    type="button"
                    class="flex flex-col gap-1 p-4 text-left transition-colors border rounded-lg cursor-pointer"
                    :class="
                      modelo.category === categoria
                        ? 'border-n-brand bg-n-brand/5'
                        : 'border-n-weak bg-transparent hover:border-n-strong'
                    "
                    @click="modelo.category = categoria"
                  >
                    <span class="flex items-center justify-between gap-2">
                      <span class="text-sm font-medium text-n-slate-12">
                        {{
                          $t(
                            `WHATSAPP_TEMPLATE_MGMT.EDITOR.CATEGORY.${categoria}.LABEL`
                          )
                        }}
                      </span>
                      <Icon
                        v-if="modelo.category === categoria"
                        icon="i-lucide-check-circle-2"
                        class="size-4 text-n-brand shrink-0"
                      />
                    </span>
                    <span class="text-xs leading-relaxed text-n-slate-11">
                      {{
                        $t(
                          `WHATSAPP_TEMPLATE_MGMT.EDITOR.CATEGORY.${categoria}.HELP`
                        )
                      }}
                    </span>
                  </button>
                </div>

                <p class="text-xs text-n-slate-10">
                  {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.CATEGORY.AUTH_NOTE') }}
                </p>
              </section>

              <section
                class="flex flex-col gap-3 p-5 border rounded-xl border-n-weak bg-n-solid-1"
              >
                <h2 class="text-sm font-medium text-n-slate-12">
                  {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.TYPE.TITLE') }}
                </h2>
                <div
                  class="flex items-start gap-3 p-4 border rounded-lg border-n-brand bg-n-brand/5"
                >
                  <Icon
                    icon="i-lucide-message-square-text"
                    class="mt-0.5 size-4 text-n-brand shrink-0"
                  />
                  <span class="flex flex-col gap-1">
                    <span class="text-sm font-medium text-n-slate-12">
                      {{
                        $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.TYPE.STANDARD.LABEL')
                      }}
                    </span>
                    <span class="text-xs leading-relaxed text-n-slate-11">
                      {{
                        $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.TYPE.STANDARD.HELP')
                      }}
                    </span>
                  </span>
                </div>
                <!-- Catálogo, Flows, pagamento e compartilhar contato ficam de fora: oferecer e
                     falhar no envio é pior do que não oferecer. -->
                <p class="text-xs text-n-slate-10">
                  {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.TYPE.OTHERS_NOTE') }}
                </p>
              </section>
            </template>

            <!-- Passo 2: identidade e conteúdo. -->
            <template v-else>
              <section
                class="flex flex-col gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1"
              >
                <h2 class="text-sm font-medium text-n-slate-12">
                  {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.IDENTITY.TITLE') }}
                </h2>

                <!-- ComboBox em vez de <select>: o nativo abre com o tema do sistema, branco no
                     meio da tela escura. -->
                <div class="grid gap-4 sm:grid-cols-2">
                  <div class="flex flex-col gap-1.5">
                    <span class="text-xs font-medium text-n-slate-11">
                      {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.IDENTITY.INBOX') }}
                    </span>
                    <ComboBox
                      v-model="inboxId"
                      :options="opcoesDeCaixa"
                      :disabled="editando"
                      :placeholder="
                        $t(
                          'WHATSAPP_TEMPLATE_MGMT.EDITOR.IDENTITY.INBOX_PLACEHOLDER'
                        )
                      "
                    />
                  </div>

                  <div class="flex flex-col gap-1.5">
                    <span class="text-xs font-medium text-n-slate-11">
                      {{
                        $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.IDENTITY.LANGUAGE')
                      }}
                    </span>
                    <ComboBox
                      v-model="modelo.language"
                      :options="IDIOMAS"
                      :disabled="editando"
                    />
                  </div>
                </div>

                <label class="flex flex-col gap-1.5">
                  <span class="flex items-baseline justify-between gap-2">
                    <span class="text-xs font-medium text-n-slate-11">
                      {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.IDENTITY.NAME') }}
                    </span>
                    <span
                      v-if="!editando"
                      class="text-xs tabular-nums text-n-slate-10"
                    >
                      {{ contagem('name') }}
                    </span>
                  </span>
                  <input
                    :value="modelo.name"
                    type="text"
                    :disabled="editando"
                    :class="CAMPO"
                    :placeholder="
                      $t(
                        'WHATSAPP_TEMPLATE_MGMT.EDITOR.IDENTITY.NAME_PLACEHOLDER'
                      )
                    "
                    @input="aoDigitarNome"
                    @blur="marcarTocado('name')"
                  />
                  <!-- A Meta não deixa trocar nome nem idioma depois: dizer isso aqui evita a
                       pergunta "por que está travado?". -->
                  <span
                    class="text-xs"
                    :class="
                      erroDe('name') ? 'text-n-ruby-11' : 'text-n-slate-10'
                    "
                  >
                    {{
                      erroDe('name')
                        ? $t(
                            `WHATSAPP_TEMPLATE_MGMT.EDITOR.ERRORS.NAME.${erroDe('name')}`
                          )
                        : editando
                          ? $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.IDENTITY.LOCKED')
                          : $t(
                              'WHATSAPP_TEMPLATE_MGMT.EDITOR.IDENTITY.NAME_HELP'
                            )
                    }}
                  </span>
                </label>
              </section>

              <section
                class="flex flex-col gap-5 p-5 border rounded-xl border-n-weak bg-n-solid-1"
              >
                <h2 class="text-sm font-medium text-n-slate-12">
                  {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.TITLE') }}
                </h2>

                <label class="flex flex-col gap-1.5">
                  <span class="flex items-baseline justify-between gap-2">
                    <span class="text-xs font-medium text-n-slate-11">
                      {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.HEADER') }}
                    </span>
                    <span class="text-xs tabular-nums text-n-slate-10">
                      {{ contagem('header') }}
                    </span>
                  </span>
                  <input
                    v-model="modelo.header"
                    type="text"
                    :class="CAMPO"
                    :placeholder="
                      $t(
                        'WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.HEADER_PLACEHOLDER'
                      )
                    "
                    @blur="marcarTocado('header')"
                  />
                  <span v-if="erroDe('header')" class="text-xs text-n-ruby-11">
                    {{
                      $t(
                        `WHATSAPP_TEMPLATE_MGMT.EDITOR.ERRORS.HEADER.${erroDe('header')}`
                      )
                    }}
                  </span>
                </label>

                <div class="flex flex-col gap-1.5">
                  <span class="flex items-baseline justify-between gap-2">
                    <span class="text-xs font-medium text-n-slate-11">
                      {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.BODY') }}
                    </span>
                    <span class="text-xs tabular-nums text-n-slate-10">
                      {{ contagem('body') }}
                    </span>
                  </span>

                  <!-- Barra e campo dividem a mesma moldura: é um controle só, não dois. -->
                  <div
                    class="overflow-hidden transition-colors border rounded-lg border-n-weak bg-n-alpha-black2 focus-within:border-n-brand"
                  >
                    <div
                      class="flex items-center gap-0.5 px-2 py-1 border-b border-n-weak"
                    >
                      <button
                        v-for="formato in FORMATOS"
                        :key="formato.chave"
                        type="button"
                        class="flex items-center justify-center transition-colors bg-transparent border-0 rounded-md cursor-pointer size-8 text-n-slate-12 hover:bg-n-alpha-2"
                        :title="
                          $t(
                            `WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.FORMAT.${formato.chave}`
                          )
                        "
                        @mousedown.prevent
                        @click="formatar(formato.marcador)"
                      >
                        <Icon :icon="formato.icone" class="size-4" />
                      </button>
                      <span class="w-px h-5 mx-1.5 bg-n-weak" />
                      <button
                        type="button"
                        class="flex items-center gap-1.5 px-2 text-xs font-medium transition-colors bg-transparent border-0 rounded-md cursor-pointer h-8 text-n-brand hover:bg-n-alpha-2"
                        @mousedown.prevent
                        @click="inserirVariavel"
                      >
                        <Icon icon="i-lucide-braces" class="size-4" />
                        {{
                          $t(
                            'WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.ADD_VARIABLE'
                          )
                        }}
                      </button>
                    </div>
                    <textarea
                      ref="corpoRef"
                      v-model="modelo.body"
                      rows="7"
                      class="w-full px-3 py-2 text-sm bg-transparent border-0 outline-none resize-y text-n-slate-12 placeholder:text-n-slate-10"
                      :placeholder="
                        $t(
                          'WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.BODY_PLACEHOLDER'
                        )
                      "
                      @blur="marcarTocado('body')"
                    />
                  </div>

                  <span
                    class="text-xs"
                    :class="
                      erroDe('body') ? 'text-n-ruby-11' : 'text-n-slate-10'
                    "
                  >
                    {{
                      erroDe('body')
                        ? $t(
                            `WHATSAPP_TEMPLATE_MGMT.EDITOR.ERRORS.BODY.${erroDe('body')}`
                          )
                        : $t(
                            'WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.FORMAT.NOTE'
                          )
                    }}
                  </span>
                </div>

                <!-- A Meta exige um exemplo por variável e usa esse valor para entender o modelo na
                     análise. Valor genérico pesa contra a aprovação, então pedimos o real. -->
                <div
                  v-if="variaveis.length"
                  class="flex flex-col gap-2.5 p-4 rounded-lg bg-n-alpha-1"
                >
                  <div class="flex flex-col gap-0.5">
                    <span class="text-xs font-medium text-n-slate-11">
                      {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.EXAMPLES') }}
                    </span>
                    <span class="text-xs leading-relaxed text-n-slate-10">
                      {{
                        $t(
                          'WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.EXAMPLES_HELP'
                        )
                      }}
                    </span>
                  </div>
                  <label
                    v-for="numero in variaveis"
                    :key="numero"
                    class="flex items-center gap-2"
                  >
                    <span
                      class="px-2 py-1 font-mono text-xs rounded-md shrink-0 bg-n-alpha-2 text-n-slate-11"
                    >
                      {{ rotuloVariavel(numero) }}
                    </span>
                    <input
                      v-model="modelo.examples[numero]"
                      type="text"
                      :class="CAMPO"
                      :placeholder="
                        $t(
                          'WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.EXAMPLE_PLACEHOLDER'
                        )
                      "
                      @blur="marcarTocado('examples')"
                    />
                  </label>
                  <span
                    v-if="erroDe('examples')"
                    class="text-xs text-n-ruby-11"
                  >
                    {{
                      $t(
                        `WHATSAPP_TEMPLATE_MGMT.EDITOR.ERRORS.EXAMPLES.${erroDe('examples')}`
                      )
                    }}
                  </span>
                </div>

                <label class="flex flex-col gap-1.5">
                  <span class="flex items-baseline justify-between gap-2">
                    <span class="text-xs font-medium text-n-slate-11">
                      {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.FOOTER') }}
                    </span>
                    <span class="text-xs tabular-nums text-n-slate-10">
                      {{ contagem('footer') }}
                    </span>
                  </span>
                  <input
                    v-model="modelo.footer"
                    type="text"
                    :class="CAMPO"
                    :placeholder="
                      $t(
                        'WHATSAPP_TEMPLATE_MGMT.EDITOR.CONTENT.FOOTER_PLACEHOLDER'
                      )
                    "
                    @blur="marcarTocado('footer')"
                  />
                  <span v-if="erroDe('footer')" class="text-xs text-n-ruby-11">
                    {{
                      $t(
                        `WHATSAPP_TEMPLATE_MGMT.EDITOR.ERRORS.FOOTER.${erroDe('footer')}`
                      )
                    }}
                  </span>
                </label>
              </section>

              <section
                class="flex flex-col gap-3 p-5 border rounded-xl border-n-weak bg-n-solid-1"
              >
                <div class="flex flex-col gap-0.5">
                  <h2 class="text-sm font-medium text-n-slate-12">
                    {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.BUTTONS.TITLE') }}
                  </h2>
                  <p class="text-xs text-n-slate-11">
                    {{
                      $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.BUTTONS.DESCRIPTION')
                    }}
                  </p>
                </div>

                <div
                  v-for="(botao, indice) in modelo.buttons"
                  :key="indice"
                  class="flex flex-col gap-3 p-3 border rounded-lg border-n-weak"
                >
                  <div class="flex items-center justify-between gap-2">
                    <span
                      class="flex items-center gap-1.5 px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
                    >
                      <Icon
                        :icon="
                          botao.type === 'URL'
                            ? 'i-lucide-external-link'
                            : 'i-lucide-reply'
                        "
                        class="size-3"
                      />
                      {{
                        $t(
                          `WHATSAPP_TEMPLATE_MGMT.EDITOR.BUTTONS.KIND.${botao.type}`
                        )
                      }}
                    </span>
                    <Button
                      icon="i-lucide-trash-2"
                      color="slate"
                      variant="ghost"
                      size="xs"
                      @click="removerBotao(indice)"
                    />
                  </div>
                  <div
                    class="grid gap-3"
                    :class="botao.type === 'URL' ? 'sm:grid-cols-2' : ''"
                  >
                    <label class="flex flex-col gap-1.5">
                      <span class="text-xs font-medium text-n-slate-11">
                        {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.BUTTONS.TEXT') }}
                      </span>
                      <input
                        v-model="botao.text"
                        type="text"
                        :maxlength="LIMITS.buttonText"
                        :class="CAMPO"
                        @blur="marcarTocado('buttons')"
                      />
                    </label>
                    <label
                      v-if="botao.type === 'URL'"
                      class="flex flex-col gap-1.5"
                    >
                      <span class="text-xs font-medium text-n-slate-11">
                        {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.BUTTONS.URL') }}
                      </span>
                      <input
                        v-model="botao.url"
                        type="url"
                        :class="CAMPO"
                        :placeholder="
                          $t(
                            'WHATSAPP_TEMPLATE_MGMT.EDITOR.BUTTONS.URL_PLACEHOLDER'
                          )
                        "
                        @blur="marcarTocado('buttons')"
                      />
                    </label>
                  </div>
                </div>

                <span v-if="erroDe('buttons')" class="text-xs text-n-ruby-11">
                  {{
                    $t(
                      `WHATSAPP_TEMPLATE_MGMT.EDITOR.ERRORS.BUTTONS.${erroDe('buttons')}`
                    )
                  }}
                </span>

                <div class="flex flex-wrap items-center gap-2">
                  <Button
                    :label="
                      $t(
                        'WHATSAPP_TEMPLATE_MGMT.EDITOR.BUTTONS.ADD_QUICK_REPLY'
                      )
                    "
                    icon="i-lucide-plus"
                    color="slate"
                    size="sm"
                    :disabled="modelo.buttons.length >= LIMITS.buttons"
                    @click="adicionarBotao('QUICK_REPLY')"
                  />
                  <Button
                    :label="$t('WHATSAPP_TEMPLATE_MGMT.EDITOR.BUTTONS.ADD_URL')"
                    icon="i-lucide-plus"
                    color="slate"
                    size="sm"
                    :disabled="modelo.buttons.length >= LIMITS.buttons"
                    @click="adicionarBotao('URL')"
                  />
                  <span class="ml-auto text-xs tabular-nums text-n-slate-10">
                    {{ modelo.buttons.length }}/{{ LIMITS.buttons }}
                  </span>
                </div>
              </section>
            </template>
          </div>

          <!-- Prévia sempre à vista, como na Meta: é o que deixa julgar a mensagem enquanto
               escreve. Fica grudada no topo para não sumir na rolagem. -->
          <aside
            v-if="etapa === 2"
            class="sticky top-0 hidden w-80 shrink-0 lg:flex lg:flex-col lg:gap-3"
          >
            <h2 class="text-sm font-medium text-n-slate-12">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.PREVIEW.TITLE') }}
            </h2>
            <TemplateBubblePreview
              :header="modelo.header"
              :body="modelo.body"
              :examples="modelo.examples"
              :footer="modelo.footer"
              :buttons="modelo.buttons"
            />
            <p class="text-xs leading-relaxed text-n-slate-10">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.PREVIEW.VARIABLE_NOTE') }}
            </p>
          </aside>
        </div>
      </div>

      <!-- Grudado embaixo: as ações somem na rolagem de um formulário deste tamanho. -->
      <div
        class="sticky bottom-0 border-t bg-n-solid-1 border-n-weak backdrop-blur-sm"
      >
        <div
          class="flex flex-wrap items-center justify-between w-full gap-3 px-6 py-3 mx-auto max-w-7xl"
        >
          <!-- Modelo novo nasce pendente; editar um aprovado tem limite de edições na Meta.
               Avisar antes do clique evita susto depois. -->
          <span class="max-w-xl text-xs leading-relaxed text-n-slate-10">
            {{
              editando
                ? $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.EDIT_NOTE')
                : $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.NEW_NOTE')
            }}
          </span>
          <div class="flex items-center gap-2 ltr:ml-auto rtl:mr-auto">
            <Button
              :label="$t('WHATSAPP_TEMPLATE_MGMT.EDITOR.CANCEL')"
              color="slate"
              variant="ghost"
              size="sm"
              @click="voltarParaLista"
            />
            <Button
              v-if="etapa === 2 && !editando"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.EDITOR.BACK')"
              color="slate"
              size="sm"
              @click="etapa = 1"
            />
            <Button
              v-if="etapa === 1"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.EDITOR.NEXT')"
              icon="i-lucide-arrow-right"
              trailing-icon
              size="sm"
              @click="etapa = 2"
            />
            <Button
              v-else
              :label="
                editando
                  ? $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.SAVE')
                  : $t('WHATSAPP_TEMPLATE_MGMT.EDITOR.SUBMIT')
              "
              size="sm"
              :is-loading="salvando"
              @click="salvar"
            />
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
