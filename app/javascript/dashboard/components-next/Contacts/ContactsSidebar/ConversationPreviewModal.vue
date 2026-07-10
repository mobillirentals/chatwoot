<script setup>
import { ref, onMounted, nextTick, provide } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import MessageApi from 'dashboard/api/inbox/message';
import MessageList from 'next/message/MessageList.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversationId: {
    type: [String, Number],
    required: true,
  },
  // Opcional: quando informado, abre a prévia já rolada até essa mensagem.
  messageId: {
    type: [String, Number],
    default: null,
  },
  // Opcional: função que busca as mensagens (deve resolver { data: { payload } }).
  // Usada quando a conversa não está acessível pelo endpoint padrão (ex.: lixeira).
  fetchMessages: {
    type: Function,
    default: null,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const currentUserId = useMapGetter('getCurrentUserID');

const messages = ref([]);
const isLoading = ref(true);
const panelRef = ref(null);

// Componentes de mensagem podem injetar este alvo para o menu de contexto.
provide('contextMenuElementTarget', panelRef);

const scrollToBottom = () => {
  if (panelRef.value) {
    panelRef.value.scrollTop = panelRef.value.scrollHeight;
  }
};

// Rola até a mensagem-alvo e dá um flash para destacá-la.
const scrollToTargetMessage = () => {
  const el = panelRef.value?.querySelector(`#message${props.messageId}`);
  if (!el) {
    scrollToBottom();
    return;
  }
  el.scrollIntoView({ block: 'center' });
  el.animate(
    [
      { backgroundColor: 'rgba(59, 130, 246, 0.18)' },
      { backgroundColor: 'transparent' },
    ],
    { duration: 1600, easing: 'ease-out' }
  );
};

onMounted(async () => {
  try {
    const params = { conversationId: props.conversationId };
    // Carrega uma janela em volta da mensagem-alvo para garantir que ela venha.
    if (props.messageId) {
      params.before = Number(props.messageId) + 100;
      params.after = Number(props.messageId) - 100;
    }
    const { data } = props.fetchMessages
      ? await props.fetchMessages()
      : await MessageApi.getPreviousMessages(params);
    messages.value = (data?.payload || [])
      .slice()
      .sort((a, b) => (a.created_at || 0) - (b.created_at || 0));
    isLoading.value = false;
    await nextTick();
    if (props.messageId) {
      scrollToTargetMessage();
    } else {
      // Abre no fim (mensagem mais recente), como na conversa real.
      scrollToBottom();
    }
  } catch {
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PREVIEW.ERROR'));
    emit('close');
  }
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
    @click.self="emit('close')"
  >
    <div
      class="flex flex-col w-full max-w-2xl overflow-hidden shadow-2xl bg-n-solid-1 rounded-xl max-h-[85vh]"
    >
      <div
        class="flex items-center justify-between px-5 py-3 border-b border-n-weak shrink-0"
      >
        <h3 class="text-base font-semibold text-n-slate-12">
          {{
            t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PREVIEW.TITLE', {
              id: conversationId,
            })
          }}
        </h3>
        <button
          class="transition-colors text-n-slate-10 hover:text-n-slate-12"
          :aria-label="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PREVIEW.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>
      <div
        v-if="isLoading"
        class="flex items-center justify-center flex-1 min-h-0 h-72 bg-n-surface-1"
      >
        <Spinner />
      </div>
      <!-- Conversa real (somente leitura): reusa o MessageList da plataforma -->
      <div
        v-else
        ref="panelRef"
        class="flex-1 min-h-0 py-4 overflow-y-auto bg-n-surface-1"
      >
        <MessageList
          v-if="messages.length"
          :messages="messages"
          :current-user-id="currentUserId"
        />
        <p v-else class="p-6 text-sm text-center text-n-slate-11">
          {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EMPTY_STATE') }}
        </p>
      </div>
    </div>
  </div>
</template>
