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
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const currentUserId = useMapGetter('getCurrentUserID');

const messages = ref([]);
const isLoading = ref(true);
const panelRef = ref(null);

// Componentes de mensagem podem injetar este alvo para o menu de contexto.
provide('contextMenuElementTarget', panelRef);

onMounted(async () => {
  try {
    const { data } = await MessageApi.getPreviousMessages({
      conversationId: props.conversationId,
    });
    messages.value = (data?.payload || [])
      .slice()
      .sort((a, b) => (a.created_at || 0) - (b.created_at || 0));
    isLoading.value = false;
    await nextTick();
    // Abre no fim (mensagem mais recente), como na conversa real.
    if (panelRef.value) {
      panelRef.value.scrollTop = panelRef.value.scrollHeight;
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
          {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PREVIEW.TITLE') }}
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
