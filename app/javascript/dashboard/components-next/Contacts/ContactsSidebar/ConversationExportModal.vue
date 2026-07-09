<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import contactAPI from 'dashboard/api/contacts';

const props = defineProps({
  contactId: {
    type: [String, Number],
    required: true,
  },
  conversations: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const selectedIds = ref(new Set());
const isExporting = ref(false);

const allSelected = computed(
  () =>
    props.conversations.length > 0 &&
    props.conversations.every(c => selectedIds.value.has(c.id))
);

const hasSelection = computed(() => selectedIds.value.size > 0);

const toggleAll = () => {
  if (allSelected.value) {
    selectedIds.value = new Set();
  } else {
    selectedIds.value = new Set(props.conversations.map(c => c.id));
  }
};

const toggleConversation = id => {
  const next = new Set(selectedIds.value);
  if (next.has(id)) {
    next.delete(id);
  } else {
    next.add(id);
  }
  selectedIds.value = next;
};

const channelIcon = conversation => {
  const type = conversation.inbox_id ? conversation.channel : '';
  if (type?.includes('Whatsapp') || type?.includes('whatsapp')) return '💬';
  if (type?.includes('Email') || type?.includes('email')) return '✉️';
  return '💬';
};

const statusLabel = status => {
  const map = {
    open: t('CONVERSATION.STATUS.OPEN'),
    resolved: t('CONVERSATION.STATUS.RESOLVED'),
    pending: t('CONVERSATION.STATUS.PENDING'),
    snoozed: t('CONVERSATION.STATUS.SNOOZED'),
  };
  return map[status] || status;
};

const formatDate = ts => {
  if (!ts) return '—';
  return new Date(ts * 1000).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const handleExport = async () => {
  if (!hasSelection.value || isExporting.value) return;

  isExporting.value = true;
  try {
    const ids = [...selectedIds.value];
    const { data } = await contactAPI.exportConversations(props.contactId, ids);

    const win = window.open('', '_blank');
    if (!win) {
      useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.POPUP_BLOCKED'));
      return;
    }
    win.document.write(data);
    win.document.close();
    emit('close');
  } catch {
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.ERROR'));
  } finally {
    isExporting.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm"
    @click.self="emit('close')"
  >
    <div
      class="bg-n-solid-1 rounded-xl shadow-2xl w-full max-w-lg mx-4 flex flex-col max-h-[80vh]"
    >
      <!-- Header -->
      <div
        class="flex items-center justify-between px-5 py-4 border-b border-n-weak shrink-0"
      >
        <div>
          <h3 class="text-base font-semibold text-n-slate-12">
            {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.TITLE') }}
          </h3>
          <p class="text-xs text-n-slate-11 mt-0.5">
            {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.SUBTITLE') }}
          </p>
        </div>
        <button
          class="text-n-slate-10 hover:text-n-slate-12 transition-colors"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <!-- Select all -->
      <div
        class="flex items-center gap-3 px-5 py-3 border-b border-n-weak shrink-0 bg-n-alpha-1"
      >
        <input
          id="select-all"
          type="checkbox"
          class="accent-woot-500 size-4 cursor-pointer"
          :checked="allSelected"
          :indeterminate="hasSelection && !allSelected"
          @change="toggleAll"
        />
        <label
          for="select-all"
          class="text-sm font-medium text-n-slate-11 cursor-pointer select-none"
        >
          {{
            allSelected
              ? t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.DESELECT_ALL')
              : t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.SELECT_ALL')
          }}
          <span class="text-n-slate-10 font-normal">
            ({{ selectedIds.size }}/{{ conversations.length }})
          </span>
        </label>
      </div>

      <!-- Conversation list -->
      <div class="flex-1 overflow-y-auto divide-y divide-n-weak">
        <div
          v-for="conv in conversations"
          :key="conv.id"
          class="flex items-start gap-3 px-5 py-3 cursor-pointer hover:bg-n-alpha-1 transition-colors"
          @click="toggleConversation(conv.id)"
        >
          <input
            :id="`conv-${conv.id}`"
            type="checkbox"
            class="accent-woot-500 size-4 mt-0.5 cursor-pointer shrink-0"
            :checked="selectedIds.has(conv.id)"
            @change.stop="toggleConversation(conv.id)"
            @click.stop
          />
          <label
            :for="`conv-${conv.id}`"
            class="flex-1 cursor-pointer select-none"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm font-medium text-n-slate-12">
                {{ channelIcon(conv) }} #{{ conv.id }}
                <span
                  class="ml-1.5 text-xs font-normal px-1.5 py-0.5 rounded-full"
                  :class="{
                    'bg-green-100 text-green-700': conv.status === 'resolved',
                    'bg-blue-100 text-blue-700': conv.status === 'open',
                    'bg-yellow-100 text-yellow-700': conv.status === 'pending',
                    'bg-gray-100 text-gray-600': conv.status === 'snoozed',
                  }"
                >
                  {{ statusLabel(conv.status) }}
                </span>
              </span>
              <span class="text-xs text-n-slate-10 shrink-0">
                {{ formatDate(conv.created_at) }}
              </span>
            </div>
            <div class="text-xs text-n-slate-10 mt-0.5 truncate">
              {{
                conv.meta?.assignee?.name
                  ? t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.AGENT', {
                      name: conv.meta.assignee.name,
                    })
                  : t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.NO_AGENT')
              }}
              <span v-if="conv.inbox_id" class="ml-2">
                · {{ conv.inbox_id }}
              </span>
            </div>
          </label>
        </div>

        <div
          v-if="conversations.length === 0"
          class="px-5 py-10 text-sm text-center text-n-slate-10"
        >
          {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EMPTY_STATE') }}
        </div>
      </div>

      <!-- Footer -->
      <div
        class="flex items-center justify-end gap-3 px-5 py-4 border-t border-n-weak shrink-0"
      >
        <button
          class="px-4 py-2 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 transition-colors"
          @click="emit('close')"
        >
          {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.CANCEL') }}
        </button>
        <button
          class="flex items-center gap-2 px-4 py-2 text-sm font-semibold rounded-lg transition-all"
          :class="
            hasSelection && !isExporting
              ? 'bg-woot-500 text-white hover:bg-woot-600 shadow-sm'
              : 'bg-n-alpha-2 text-n-slate-9 cursor-not-allowed'
          "
          :disabled="!hasSelection || isExporting"
          @click="handleExport"
        >
          <span
            v-if="isExporting"
            class="i-lucide-loader-circle animate-spin size-4"
          />
          <span v-else class="i-lucide-file-text size-4" />
          {{
            isExporting
              ? t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.GENERATING')
              : t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.BUTTON', {
                  count: selectedIds.size,
                })
          }}
        </button>
      </div>
    </div>
  </div>
</template>
