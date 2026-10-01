<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAparencia } from 'dashboard/composables/useAparencia';
import {
  uploadFile,
  removerArquivoEnviado,
} from 'dashboard/helper/uploadHelper';
import {
  reaplicaCorAposTrocaDeTema,
  TEMAS_PERSONALIZADOS,
  FUNDOS_PRONTOS,
  MEDIDA_RECOMENDADA,
  CLARIDADE_PADRAO,
  LIMITE_DE_ENVIOS,
  comprimirImagem,
} from 'dashboard/helper/aparencia';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { setColorTheme } from 'dashboard/helper/themeHelper.js';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
const {
  envios,
  registrarEnvios,
  temaPersonalizadoSalvo,
  fundoDaConversaSalvo,
  claridadeSalva,
  aplicarVisual,
  salvarPreferencias,
} = useAparencia();

const dialogRef = ref(null);
// enquanto o diálogo está escondido, um escudo engole os cliques: sem ele a pessoa acerta um
// botão que não está vendo, e um clique no vazio seria entendido como "clicou fora, feche"
const espiando = ref(false);
// A prévia só faz sentido com a conversa na tela: em Configurações, por exemplo, não há onde o
// fundo aparecer. Nesse caso o diálogo não some — a escolha é às cegas, mas sem piscar à toa.
const temConversaNaTela = ref(false);
const conferirConversa = () => {
  temConversaNaTela.value = Boolean(
    document.querySelector('.conversation-panel')
  );
};
const conteudoRef = ref(null);
// quanto tempo a conversa fica à mostra depois de cada escolha
const TEMPO_DA_ESPIADA = 1000;
let voltaDoEspiar = null;
let comecouAEspiar = 0;

// Enquanto a pessoa experimenta, o diálogo sai da frente: o fundo e o tema já estão aplicados
// atrás dele, então o que falta é poder ver. Some ao mexer e volta sozinho; o botão Espiar
// segura enquanto estiver pressionado, pra quem quiser olhar com calma.
let janelaDoDialogo = null;
const pegarJanela = () => {
  janelaDoDialogo = conteudoRef.value?.closest('dialog') || janelaDoDialogo;
  return janelaDoDialogo;
};

const mostrarDialogo = visivel => {
  espiando.value = !visivel;
  const janela = pegarJanela();
  if (!janela) return;

  // a classe cuida do véu do modal; a opacidade vai direto no elemento porque a moldura do
  // diálogo carrega `transition-all` e classes utilitárias próprias, e estilo inline não
  // depende de quem ganha na folha de estilo
  janela.classList.toggle('aparencia-espiando', !visivel);
  // some o diálogo inteiro, não só a moldura de dentro: o próprio <dialog> tem fundo e sombra,
  // e era ele que continuava desenhando um retângulo escuro sobre a conversa.
  // A transição vai junto, inline: a moldura carrega `transition-all duration-300` do
  // componente, e era esse 300ms que deixava a saída arrastada.
  janela.style.transition = 'opacity 120ms ease-out';
  janela.style.opacity = visivel ? '' : '0';
  janela.style.boxShadow = visivel ? '' : 'none';
};

// Ajustar a claridade é diferente de escolher uma imagem: a pessoa precisa ver a régua e o
// número enquanto mexe. Então o diálogo não some — some tudo o que há nele, menos o controle.
const mostrarSoClaridade = so => {
  if (!temConversaNaTela.value) return;

  const janela = pegarJanela();
  if (!janela) return;

  clearTimeout(voltaDoEspiar);
  janela.classList.toggle('aparencia-so-claridade', so);
  if (!so) {
    janela.style.opacity = '';
    janela.style.boxShadow = '';
    janela.style.transition = '';
  }
};

const espiarRapido = () => {
  if (!temConversaNaTela.value) return;

  mostrarDialogo(false);
  clearTimeout(voltaDoEspiar);
  voltaDoEspiar = setTimeout(() => mostrarDialogo(true), TEMPO_DA_ESPIADA);
};

const pararEspiar = () => {
  clearTimeout(voltaDoEspiar);
  mostrarDialogo(true);
};

// Soltar devolve o diálogo, mas nunca antes de TEMPO_DA_ESPIADA: num clique comum o aperta e
// solta dura menos de 150 ms, e o diálogo sumia e voltava tão rápido que o botão parecia morto.
const soltarEspiada = () => {
  const falta = TEMPO_DA_ESPIADA - (Date.now() - comecouAEspiar);
  clearTimeout(voltaDoEspiar);
  if (falta <= 0) {
    mostrarDialogo(true);
    return;
  }

  voltaDoEspiar = setTimeout(() => mostrarDialogo(true), falta);
};

// um gesto só serve aos dois usos: clicar mostra a conversa por um instante, segurar mantém
// enquanto o dedo ou o mouse estiver pressionado. `pointerdown` cobre mouse e toque de uma vez —
// e o retorno vem do `pointerup` na janela, porque o escudo some com o ponteiro de cima do botão
const comecarEspiar = () => {
  if (!temConversaNaTela.value) return;

  clearTimeout(voltaDoEspiar);
  comecouAEspiar = Date.now();
  mostrarDialogo(false);
  window.addEventListener('pointerup', soltarEspiada, { once: true });
};
const arquivoRef = ref(null);
const enviando = ref(false);
const salvando = ref(false);

const accountId = useMapGetter('getCurrentAccountId');

const temaDoSistemaSalvo = () =>
  LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';

// O que está sendo experimentado agora. A tela muda junto, mas nada é gravado até o Salvar —
// e o Cancelar devolve tudo ao que estava.
const rascunho = ref({
  base: 'auto',
  proprio: '',
  fundo: '',
  claridade: CLARIDADE_PADRAO,
});

// Prévia do claro/escuro sem gravar nada: o setColorTheme oficial lê a preferência do
// localStorage, que aqui só é escrita no Salvar — usá-lo na prévia mostraria o tema antigo.
const aplicarTemaBase = chave => {
  const escuro =
    chave === 'dark' ||
    (chave === 'auto' &&
      window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.body.classList.toggle('dark', escuro);
  document.documentElement.style.setProperty(
    'color-scheme',
    escuro ? 'dark' : 'light'
  );
};

const temasBase = [
  { chave: 'light', icone: 'i-lucide-sun' },
  { chave: 'dark', icone: 'i-lucide-moon' },
  { chave: 'auto', icone: 'i-lucide-monitor' },
];

const temasProprios = computed(() =>
  Object.entries(TEMAS_PERSONALIZADOS).map(([chave, tema]) => ({
    chave,
    rotulo: tema.rotulo,
    // a amostra usa o mesmo matiz do tema, então a bolinha nunca mente sobre a cor
    cor: `hsl(${tema.matiz} ${tema.saturacao + 25}% 55%)`,
  }))
);

const houveMudanca = computed(
  () =>
    rascunho.value.proprio !== temaPersonalizadoSalvo.value ||
    rascunho.value.fundo !== fundoDaConversaSalvo.value ||
    rascunho.value.base !== temaDoSistemaSalvo() ||
    rascunho.value.claridade !== claridadeSalva.value
);

const escolherTemaBase = chave => {
  espiarRapido();
  rascunho.value = { ...rascunho.value, base: chave };
  aplicarTemaBase(chave);
  // a cor acompanha o tema: a escala dela parte da claridade de quem está em uso
  reaplicaCorAposTrocaDeTema();
};

const escolherCor = chave => {
  espiarRapido();
  const proprio = chave === rascunho.value.proprio ? '' : chave;
  rascunho.value = { ...rascunho.value, proprio };
  aplicarVisual({ tema: proprio });
  // sem cor, a interface volta à escala de cinzas do tema escolhido
  if (!proprio) aplicarTemaBase(rascunho.value.base);
};

const escolherFundo = url => {
  espiarRapido();
  rascunho.value = { ...rascunho.value, fundo: url };
  aplicarVisual({ fundo: url });
};

// Durante o arraste o diálogo FICA: a régua e o número são o que a pessoa está olhando. A
// espiada acontece ao soltar, quando o que importa passa a ser o resultado.
const ajustarClaridade = evento => {
  mostrarSoClaridade(true);
  const claridade = Number(evento.target.value);
  rascunho.value = { ...rascunho.value, claridade };
  aplicarVisual({ claridade });
};

const enviarImagem = async evento => {
  const arquivo = evento.target.files?.[0];
  if (!arquivo) return;

  enviando.value = true;
  try {
    // imagem grande é reduzida aqui mesmo, antes de subir: a tela nunca mostra mais que a medida
    // recomendada, e o que passa disso é só peso no carregamento de todo dia
    const pronta = await comprimirImagem(arquivo);
    const { fileUrl, blobId } = await uploadFile(pronta, accountId.value);

    // cada pessoa guarda no máximo LIMITE_DE_ENVIOS imagens próprias: a mais antiga sai para a
    // nova entrar, e o arquivo dela é apagado no servidor em vez de ficar ocupando espaço
    const lista = [...envios.value, { url: fileUrl, blobId }];
    const saindo = lista.splice(
      0,
      Math.max(0, lista.length - LIMITE_DE_ENVIOS)
    );
    await registrarEnvios(lista);
    await Promise.all(
      saindo.map(item =>
        removerArquivoEnviado(item.blobId, accountId.value).catch(() => {})
      )
    );

    escolherFundo(fileUrl);
  } catch (error) {
    useAlert(t('APPEARANCE.BACKGROUND.UPLOAD_FAILED'));
  } finally {
    enviando.value = false;
    evento.target.value = '';
  }
};

const restaurarSalvo = () => {
  rascunho.value = {
    base: temaDoSistemaSalvo(),
    proprio: temaPersonalizadoSalvo.value,
    fundo: fundoDaConversaSalvo.value,
    claridade: claridadeSalva.value,
  };
  aplicarVisual({
    tema: temaPersonalizadoSalvo.value,
    fundo: fundoDaConversaSalvo.value,
    claridade: claridadeSalva.value,
  });
  if (!temaPersonalizadoSalvo.value) aplicarTemaBase(temaDoSistemaSalvo());
};

const salvar = async () => {
  salvando.value = true;
  try {
    await salvarPreferencias({
      tema: rascunho.value.proprio,
      fundo: rascunho.value.fundo,
      claridade: rascunho.value.claridade,
    });
    LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_SCHEME, rascunho.value.base);
    // a partir daqui vale o caminho oficial, que lê a preferência recém-gravada
    setColorTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);
    useAlert(t('APPEARANCE.SAVED'));
    dialogRef.value?.close();
  } catch (error) {
    useAlert(t('APPEARANCE.SAVE_FAILED'));
  } finally {
    salvando.value = false;
  }
};

const fechar = () => dialogRef.value?.close();

const abrir = () => {
  conferirConversa();
  espiando.value = false;
  if (janelaDoDialogo) {
    janelaDoDialogo.style.opacity = '';
    janelaDoDialogo.style.boxShadow = '';
    janelaDoDialogo.classList.remove(
      'aparencia-espiando',
      'aparencia-so-claridade'
    );
  }
  pararEspiar();
  restaurarSalvo();
  dialogRef.value?.open();
};

defineExpose({ abrir, dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="t('APPEARANCE.TITLE')"
    :description="t('APPEARANCE.DESCRIPTION')"
    @confirm="salvar"
    @close="restaurarSalvo"
  >
    <div v-if="espiando" class="escudo-espiar" />
    <div ref="conteudoRef" class="flex flex-col gap-5">
      <!-- tema e cores dividem a linha: são escolhas curtas, e empilhá-las só rendia rolagem -->
      <section class="grid gap-x-6 gap-y-4 sm:grid-cols-[auto_1fr]">
        <div class="flex flex-col gap-2">
          <h4 class="text-sm font-medium text-n-slate-12">
            {{ t('APPEARANCE.THEME.TITLE') }}
          </h4>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="tema in temasBase"
              :key="tema.chave"
              type="button"
              class="opcao"
              :class="{ 'opcao--ativa': rascunho.base === tema.chave }"
              @click="escolherTemaBase(tema.chave)"
            >
              <Icon :icon="tema.icone" class="size-4" />
              {{ t(`APPEARANCE.THEME.${tema.chave.toUpperCase()}`) }}
            </button>
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <div class="flex flex-wrap items-baseline gap-x-2">
            <h4 class="text-sm font-medium text-n-slate-12">
              {{ t('APPEARANCE.THEME.CUSTOM_TITLE') }}
            </h4>
            <p class="text-xs text-n-slate-10">
              {{ t('APPEARANCE.THEME.CUSTOM_HINT') }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="tema in temasProprios"
              :key="tema.chave"
              type="button"
              class="opcao"
              :class="{ 'opcao--ativa': rascunho.proprio === tema.chave }"
              @click="escolherCor(tema.chave)"
            >
              <span
                class="rounded-full size-4 shrink-0"
                :style="{ backgroundColor: tema.cor }"
              />
              {{ tema.rotulo }}
            </button>
          </div>
        </div>
      </section>

      <section class="flex flex-col gap-3">
        <div class="flex flex-wrap items-baseline gap-x-2">
          <h4 class="text-sm font-medium text-n-slate-12">
            {{ t('APPEARANCE.BACKGROUND.TITLE') }}
          </h4>
          <p class="text-xs text-n-slate-10">
            {{
              t('APPEARANCE.BACKGROUND.HINT', {
                width: MEDIDA_RECOMENDADA.largura,
                height: MEDIDA_RECOMENDADA.altura,
              })
            }}
          </p>
        </div>

        <div class="grid grid-cols-3 gap-2 sm:grid-cols-6">
          <button
            type="button"
            class="miniatura flex items-center justify-center text-xs"
            :class="
              !rascunho.fundo
                ? 'miniatura--escolhida text-n-slate-12'
                : 'text-n-slate-11'
            "
            @click="escolherFundo('')"
          >
            {{ t('APPEARANCE.BACKGROUND.NONE') }}
            <span v-if="!rascunho.fundo" class="marca-escolhida">
              <Icon icon="i-lucide-check" class="size-3" />
            </span>
          </button>

          <button
            v-for="fundo in FUNDOS_PRONTOS"
            :key="fundo.id"
            type="button"
            class="miniatura"
            :class="{ 'miniatura--escolhida': rascunho.fundo === fundo.url }"
            :title="
              t(`APPEARANCE.BACKGROUND.PRESETS.${fundo.id.toUpperCase()}`)
            "
            @click="escolherFundo(fundo.url)"
          >
            <img
              :src="fundo.url"
              :alt="
                t(`APPEARANCE.BACKGROUND.PRESETS.${fundo.id.toUpperCase()}`)
              "
              class="object-cover w-full h-full"
              loading="lazy"
            />
            <span v-if="rascunho.fundo === fundo.url" class="marca-escolhida">
              <Icon icon="i-lucide-check" class="size-3" />
            </span>
          </button>

          <button
            v-for="envio in envios"
            :key="envio.blobId"
            type="button"
            class="miniatura"
            :class="{ 'miniatura--escolhida': rascunho.fundo === envio.url }"
            :title="t('APPEARANCE.BACKGROUND.YOURS')"
            @click="escolherFundo(envio.url)"
          >
            <img
              :src="envio.url"
              :alt="t('APPEARANCE.BACKGROUND.YOURS')"
              class="object-cover w-full h-full"
            />
            <span class="etiqueta-sua">{{
              t('APPEARANCE.BACKGROUND.YOURS')
            }}</span>
            <span v-if="rascunho.fundo === envio.url" class="marca-escolhida">
              <Icon icon="i-lucide-check" class="size-3" />
            </span>
          </button>
          <button
            type="button"
            class="miniatura miniatura--envio"
            :disabled="enviando"
            @click="arquivoRef.click()"
          >
            <template v-if="enviando">
              <Icon icon="i-lucide-loader-circle" class="size-4 animate-spin" />
              <span class="text-[11px]">{{
                t('APPEARANCE.BACKGROUND.SENDING')
              }}</span>
            </template>
            <template v-else>
              <Icon icon="i-lucide-cloud-upload" class="size-4" />
              <span class="text-[11px] leading-tight text-n-slate-12">
                {{ t('APPEARANCE.BACKGROUND.UPLOAD') }}
              </span>
              <span class="text-[10px] leading-tight text-n-slate-10">
                {{ t('APPEARANCE.BACKGROUND.FORMATS') }}
              </span>
            </template>
          </button>
        </div>

        <!-- régua na mesma linha do rótulo: é um controle só, e assim não come uma faixa inteira -->
        <div
          v-if="rascunho.fundo"
          class="flex items-center gap-3 bloco-claridade"
        >
          <label
            for="claridade-do-fundo"
            class="text-sm shrink-0 text-n-slate-11"
          >
            {{ t('APPEARANCE.BACKGROUND.BRIGHTNESS') }}
          </label>
          <input
            id="claridade-do-fundo"
            type="range"
            min="0"
            max="100"
            step="5"
            :value="rascunho.claridade"
            class="regua"
            @input="ajustarClaridade"
            @change="mostrarSoClaridade(false)"
            @pointerup="mostrarSoClaridade(false)"
          />
          <span
            class="w-10 text-sm text-end tabular-nums shrink-0 text-n-slate-11"
          >
            {{ rascunho.claridade }}%
          </span>
        </div>

        <input
          ref="arquivoRef"
          type="file"
          accept="image/png, image/jpeg, image/webp"
          class="hidden"
          @change="enviarImagem"
        />
      </section>
    </div>

    <!-- o Espiar divide a barra com Cancelar e Salvar: é ação do diálogo, e sozinho numa linha
         custava altura que vale mais para as miniaturas -->
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          v-if="temConversaNaTela"
          type="button"
          :label="t('APPEARANCE.PEEK')"
          icon="i-lucide-eye"
          variant="ghost"
          color="slate"
          @pointerdown="comecarEspiar"
        />
        <span v-else />
        <div class="flex items-center gap-3">
          <Button
            type="button"
            variant="faded"
            color="slate"
            :label="t('APPEARANCE.CANCEL')"
            @click="fechar"
          />
          <Button
            type="submit"
            color="blue"
            :label="t('APPEARANCE.SAVE')"
            :is-loading="salvando"
            :disabled="!houveMudanca || salvando"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>

<style scoped>
/* A seleção não pode depender só da cor da borda: o diálogo tem filtro de fundo
   (backdrop-blur) e o Chrome não repinta essa troca sozinho — a marca só aparecia quando
   outro evento forçava o repaint. Camada própria (translateZ) e um sinal que muda de
   geometria (anel + marca de confirmado) resolvem os dois lados. */
.escudo-espiar {
  position: fixed;
  inset: 0;
  z-index: 9999;
}

/* chip de escolha: o mesmo desenho serve pro tema e pra cor, e com padding menor cabem os seis
   matizes em duas linhas ao lado do tema */
.opcao {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  padding: 0.375rem 0.625rem;
  font-size: 0.8125rem;
  color: rgb(var(--slate-11));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 0.5rem;
  transition: background-color 0.15s ease;
}

.opcao:hover {
  background: rgb(var(--slate-3) / 0.5);
}

.opcao--ativa {
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-3));
  border-color: rgb(var(--blue-9));
}

.miniatura {
  position: relative;
  height: 4.5rem;
  overflow: hidden;
  border: 1px solid rgb(var(--slate-5));
  border-radius: 0.5rem;
  transform: translateZ(0);
  color: rgb(var(--slate-11));
  transition:
    box-shadow 0.15s ease,
    border-color 0.15s ease;
}

.miniatura:hover {
  border-color: rgb(var(--slate-8));
}

/* o envio é uma ação, não uma opção: borda tracejada separa um do outro sem precisar de rótulo */
.miniatura--envio {
  display: flex;
  flex-direction: column;
  gap: 0.125rem;
  align-items: center;
  justify-content: center;
  padding-inline: 0.25rem;
  text-align: center;
  border-style: dashed;
}

.miniatura--envio:disabled {
  cursor: progress;
}

.miniatura--escolhida {
  border-color: rgb(var(--blue-9));
  box-shadow:
    0 0 0 2px rgb(var(--blue-9)),
    0 4px 12px rgb(0 0 0 / 0.25);
}

.etiqueta-sua {
  position: absolute;
  inset-inline-start: 0.25rem;
  bottom: 0.25rem;
  padding: 0.0625rem 0.375rem;
  font-size: 10px;
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-1) / 0.75);
  border-radius: 999px;
}

.marca-escolhida {
  position: absolute;
  top: 0.25rem;
  inset-inline-end: 0.25rem;
  display: grid;
  place-content: center;
  width: 1.125rem;
  height: 1.125rem;
  color: rgb(var(--slate-1));
  background: rgb(var(--blue-9));
  border-radius: 999px;
}

.regua {
  flex: 1;
  min-width: 0;
  height: 0.25rem;
  appearance: none;
  background: linear-gradient(
    to right,
    rgb(var(--slate-6)),
    rgb(var(--blue-9))
  );
  border-radius: 999px;
  cursor: pointer;
}

.regua::-webkit-slider-thumb {
  width: 1rem;
  height: 1rem;
  appearance: none;
  background: rgb(var(--slate-12));
  border: 2px solid rgb(var(--blue-9));
  border-radius: 999px;
}

.regua::-moz-range-thumb {
  width: 1rem;
  height: 1rem;
  background: rgb(var(--slate-12));
  border: 2px solid rgb(var(--blue-9));
  border-radius: 999px;
}
</style>

<style>
/* Espiar precisa sumir de verdade: além do conteúdo, sai o véu escuro que o diálogo modal joga
   sobre a página — é ele que mais atrapalha quem está avaliando uma imagem de fundo. */
dialog {
  transition: opacity 120ms ease-out;
}

/* no ajuste da claridade o diálogo não some: o que some é tudo nele, menos o controle */
dialog.aparencia-so-claridade,
dialog.aparencia-so-claridade form {
  background: transparent !important;
  box-shadow: none !important;
  backdrop-filter: none !important;
}

/* o diálogo rola (tem muita miniatura); escondido, a barra dele ficava sobrando na tela */
dialog.aparencia-so-claridade {
  overflow: hidden !important;
  scrollbar-width: none;
}

dialog.aparencia-so-claridade::-webkit-scrollbar {
  display: none;
}

dialog.aparencia-so-claridade form {
  visibility: hidden;
}

dialog.aparencia-so-claridade .bloco-claridade {
  visibility: visible;
  padding: 0.75rem 1rem;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 0.75rem;
  box-shadow: 0 12px 32px rgb(0 0 0 / 0.35);
}

dialog.aparencia-so-claridade::backdrop {
  background: transparent !important;
  backdrop-filter: none !important;
}

dialog.aparencia-espiando {
  opacity: 0 !important;
  box-shadow: none !important;
}

dialog.aparencia-espiando::backdrop {
  background: transparent !important;
  backdrop-filter: none !important;
}

@media (prefers-reduced-motion: reduce) {
  dialog {
    transition: none;
  }
}
</style>
