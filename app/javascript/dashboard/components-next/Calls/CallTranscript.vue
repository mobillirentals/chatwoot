<script setup>
import { computed, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { timeStampAppendedURL } from 'dashboard/helper/URLHelper';

const props = defineProps({
  segments: { type: Array, required: true },
  recordingUrl: { type: String, default: '' },
  agentName: { type: String, default: '' },
  contactName: { type: String, default: '' },
});

const { t } = useI18n();

const audioPlayer = useTemplateRef('audioPlayer');
const timeline = useTemplateRef('timeline');
const lista = useTemplateRef('lista');

const isPlaying = ref(false);
const currentTime = ref(0);
const duration = ref(0);

const audioUrl = computed(() =>
  props.recordingUrl ? timeStampAppendedURL(props.recordingUrl) : ''
);

const nomeDoAtendente = computed(
  () => props.agentName || t('CONVERSATION.VOICE_CALL.SPEAKER_AGENT')
);
const nomeDoCliente = computed(
  () => props.contactName || t('CONVERSATION.VOICE_CALL.SPEAKER_CONTACT')
);
const nomeDe = speaker =>
  speaker === 'agent' ? nomeDoAtendente.value : nomeDoCliente.value;

// O áudio só informa a duração depois de carregar, e arquivo de MediaRecorder às vezes nem aí. O
// fim da última fala é um piso confiável, senão as faixas colapsariam em zero.
const totalSeconds = computed(() => {
  const fimDasFalas = props.segments.reduce(
    (max, s) => Math.max(max, s.end),
    0
  );
  const real = Number.isFinite(duration.value) ? duration.value : 0;
  return Math.max(real, fimDasFalas, 1);
});

const formatTime = seconds => {
  if (!Number.isFinite(seconds)) return '0:00';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
};

const activeIndex = computed(() =>
  props.segments.findIndex(
    s => currentTime.value >= s.start && currentTime.value < s.end
  )
);

// Falas seguidas da mesma pessoa viram um bloco só. Repetir o nome em cada linha, como a primeira
// versão fazia, empurrava o texto para a direita e fazia a conversa parecer mais picada do que é.
const turnos = computed(() => {
  const blocos = [];

  props.segments.forEach((segmento, indice) => {
    const ultimo = blocos[blocos.length - 1];
    const fala = { ...segmento, indice };
    if (ultimo && ultimo.speaker === segmento.speaker) {
      ultimo.falas.push(fala);
      return;
    }
    blocos.push({
      speaker: segmento.speaker,
      nome: nomeDe(segmento.speaker),
      inicio: segmento.start,
      falas: [fala],
    });
  });

  return blocos;
});

// Uma faixa por lado: onde cada um falou ao longo da chamada. Mostra num relance se o atendente
// monopolizou a conversa.
const trackFor = speaker =>
  props.segments
    .filter(s => s.speaker === speaker)
    .map(s => ({
      key: `${s.speaker}-${s.start}`,
      left: `${(s.start / totalSeconds.value) * 100}%`,
      width: `${Math.max(((s.end - s.start) / totalSeconds.value) * 100, 0.6)}%`,
    }));

const faixas = computed(() => [
  { chave: 'agent', nome: nomeDoAtendente.value, barras: trackFor('agent') },
  { chave: 'contact', nome: nomeDoCliente.value, barras: trackFor('contact') },
]);

const playheadLeft = computed(
  () => `${Math.min((currentTime.value / totalSeconds.value) * 100, 100)}%`
);

// Arquivo de MediaRecorder costuma chegar sem duração no cabeçalho, e em desenvolvimento o Rails
// serve o áudio sem suporte a range: até o navegador varrer o arquivo inteiro, `duration` fica
// Infinity e atribuir `currentTime` não faz nada. Mandar o cursor para o fim força essa varredura.
const forcarVarredura = () => {
  const el = audioPlayer.value;
  if (!el) return;
  const aoAndar = () => {
    el.removeEventListener('timeupdate', aoAndar);
    el.currentTime = 0;
    duration.value = el.duration;
  };
  el.addEventListener('timeupdate', aoAndar);
  try {
    el.currentTime = Number.MAX_SAFE_INTEGER;
  } catch (_) {
    /* noop */
  }
};

const onLoadedMetadata = () => {
  const el = audioPlayer.value;
  duration.value = el?.duration ?? 0;
  if (!Number.isFinite(duration.value)) forcarVarredura();
};
const onTimeUpdate = () => {
  currentTime.value = audioPlayer.value?.currentTime ?? 0;
};
const onEnded = () => {
  isPlaying.value = false;
};

const playOrPause = () => {
  const el = audioPlayer.value;
  if (!el) return;
  if (isPlaying.value) {
    el.pause();
    isPlaying.value = false;
    return;
  }
  el.play();
  isPlaying.value = true;
};

const pularPara = segundos => {
  const el = audioPlayer.value;
  if (!el) return;
  // Enquanto o arquivo não foi varrido não há intervalo buscável, e a atribuição vira no-op.
  if (!el.seekable.length) forcarVarredura();
  el.currentTime = segundos;
  currentTime.value = segundos;
  if (!isPlaying.value) {
    el.play();
    isPlaying.value = true;
  }
};

const irPara = segmento => pularPara(segmento.start);

const pularPelaFaixa = evento => {
  const area = timeline.value;
  if (!area) return;
  const { left, width } = area.getBoundingClientRect();
  if (!width) return;
  const proporcao = Math.min(Math.max((evento.clientX - left) / width, 0), 1);
  pularPara(proporcao * totalSeconds.value);
};

// Acompanhar a reprodução só serve se a fala corrente estiver à vista.
watch(activeIndex, indice => {
  if (indice < 0 || !lista.value) return;
  const linha = lista.value.querySelector(`[data-fala="${indice}"]`);
  if (linha) linha.scrollIntoView({ block: 'nearest' });
});
</script>

<template>
  <div
    class="flex flex-col w-full overflow-hidden border rounded-xl bg-n-alpha-white border-n-container"
  >
    <audio
      ref="audioPlayer"
      class="hidden"
      preload="auto"
      playsinline
      @loadedmetadata="onLoadedMetadata"
      @timeupdate="onTimeUpdate"
      @ended="onEnded"
    >
      <source :src="audioUrl" />
    </audio>

    <!-- Transporte e quem falou quando. A linha vertical é onde o áudio está; clicar na faixa pula. -->
    <div class="flex flex-col gap-2.5 p-3 border-b border-n-container">
      <div class="flex items-center gap-2">
        <button
          type="button"
          class="grid border-0 rounded-full size-6 place-content-center bg-n-slate-12 text-n-slate-1"
          :aria-label="
            isPlaying
              ? $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_PAUSE')
              : $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_PLAY')
          "
          @click="playOrPause"
        >
          <Icon
            class="size-3.5"
            :icon="
              isPlaying
                ? 'i-teenyicons-pause-small-solid'
                : 'i-teenyicons-play-small-solid'
            "
          />
        </button>
        <span class="text-[11px] tabular-nums text-n-slate-11">
          {{ formatTime(currentTime) }}
        </span>
        <span class="text-[11px] text-n-slate-10">/</span>
        <span class="text-[11px] tabular-nums text-n-slate-10">
          {{ formatTime(totalSeconds) }}
        </span>

        <span class="flex items-center gap-3 ml-auto">
          <span
            v-for="faixa in faixas"
            :key="`legenda-${faixa.chave}`"
            class="flex items-center gap-1.5 text-[10px] text-n-slate-11 max-w-28"
          >
            <span
              class="rounded-sm size-2 shrink-0"
              :class="faixa.chave === 'agent' ? 'bg-n-teal-9' : 'bg-n-slate-9'"
            />
            <span class="truncate">{{ faixa.nome }}</span>
          </span>
        </span>
      </div>

      <button
        ref="timeline"
        type="button"
        class="relative flex flex-col w-full gap-1 p-0 bg-transparent border-0 cursor-pointer"
        :aria-label="$t('CONVERSATION.VOICE_CALL.TRANSCRIPT_SEEK')"
        @click="pularPelaFaixa"
      >
        <span
          v-for="faixa in faixas"
          :key="faixa.chave"
          class="relative block w-full h-2 rounded bg-n-alpha-2"
        >
          <span
            v-for="barra in faixa.barras"
            :key="barra.key"
            class="absolute inset-y-0 rounded-sm"
            :class="faixa.chave === 'agent' ? 'bg-n-teal-9' : 'bg-n-slate-9'"
            :style="{ left: barra.left, width: barra.width }"
          />
        </span>
        <span
          class="absolute inset-y-0 w-px pointer-events-none bg-n-slate-12"
          :style="{ left: playheadLeft }"
        />
      </button>
    </div>

    <div ref="lista" class="flex flex-col gap-2.5 p-3 overflow-y-auto max-h-80">
      <div
        v-for="turno in turnos"
        :key="`${turno.speaker}-${turno.inicio}`"
        class="flex flex-col gap-0.5"
      >
        <span
          class="text-[11px] font-medium"
          :class="
            turno.speaker === 'agent' ? 'text-n-teal-11' : 'text-n-slate-12'
          "
        >
          {{ turno.nome }}
        </span>
        <button
          v-for="fala in turno.falas"
          :key="fala.start"
          :data-fala="fala.indice"
          type="button"
          class="grid w-full gap-2 px-2 py-1 -mx-2 text-left border-0 rounded-md grid-cols-[2.1rem_minmax(0,1fr)]"
          :class="
            fala.indice === activeIndex
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'bg-transparent text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="irPara(fala)"
        >
          <span class="text-[10px] tabular-nums pt-px text-n-slate-10">
            {{ formatTime(fala.start) }}
          </span>
          <span class="text-xs leading-snug break-words">{{ fala.text }}</span>
        </button>
      </div>
    </div>
  </div>
</template>
