<script setup>
import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import contactAPI from 'dashboard/api/contacts';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationCard from 'dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue';

const { t } = useI18n();
const route = useRoute();

const conversations = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);
const contactsById = useMapGetter('contacts/getContactById');
const stateInbox = useMapGetter('inboxes/getInboxById');
const accountLabels = useMapGetter('labels/getLabels');
const currentUser = useMapGetter('getCurrentUser');

const accountLabelsValue = computed(() => accountLabels.value);

const uiFlags = useMapGetter('contactConversations/getUIFlags');
const isFetching = computed(() => uiFlags.value.isFetching);

const contactId = computed(() => route.params.contactId);

const contactConversations = computed(
  () => conversations.value(contactId.value) || []
);

const canExport = computed(() => {
  const role = currentUser.value?.role;
  return role === 'administrator' || role === 'supervisor';
});

// ── Filtros: período (client-side) + busca nas mensagens (backend) ────
const periodDays = ref(null);
const searchQuery = ref('');
const matchedIds = ref(null); // null = sem busca; Set = ids que casaram
const isSearching = ref(false);

const periods = computed(() => [
  {
    value: null,
    label: t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.PERIOD_ALL'),
  },
  { value: 7, label: t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.PERIOD_7D') },
  { value: 30, label: t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.PERIOD_30D') },
  { value: 90, label: t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.PERIOD_90D') },
]);

const displayedConversations = computed(() => {
  let list = contactConversations.value;

  if (periodDays.value) {
    const cutoff = Date.now() / 1000 - periodDays.value * 86400;
    list = list.filter(
      c => (c.last_activity_at || c.created_at || 0) >= cutoff
    );
  }

  if (matchedIds.value) {
    list = list.filter(c => matchedIds.value.has(c.id));
  }

  return list;
});

let searchTimer = null;
let searchController = null;

const runSearch = async query => {
  if (searchController) searchController.abort();
  searchController = new AbortController();
  isSearching.value = true;
  try {
    const { data } = await contactAPI.searchConversations(
      contactId.value,
      query,
      { signal: searchController.signal }
    );
    matchedIds.value = new Set(data.conversation_ids || []);
  } catch (error) {
    if (error?.code === 'ERR_CANCELED' || error?.name === 'CanceledError') {
      return;
    }
    matchedIds.value = new Set();
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.SEARCH_ERROR'));
  } finally {
    isSearching.value = false;
  }
};

watch(searchQuery, value => {
  const query = value.trim();
  clearTimeout(searchTimer);
  if (!query) {
    if (searchController) searchController.abort();
    matchedIds.value = null;
    isSearching.value = false;
    return;
  }
  isSearching.value = true;
  searchTimer = setTimeout(() => runSearch(query), 350);
});

// ── Seleção inline para exportação em PDF ─────────────────────────
const isSelecting = ref(false);
const selectedIds = ref(new Set());
const isExporting = ref(false);

const allSelected = computed(
  () =>
    displayedConversations.value.length > 0 &&
    displayedConversations.value.every(c => selectedIds.value.has(c.id))
);
const hasSelection = computed(() => selectedIds.value.size > 0);
const selectionLabel = computed(
  () => `(${selectedIds.value.size}/${displayedConversations.value.length})`
);

// Mantém a seleção coerente com o que está visível após filtrar.
watch(displayedConversations, list => {
  if (selectedIds.value.size === 0) return;
  const visible = new Set(list.map(c => c.id));
  const next = new Set([...selectedIds.value].filter(id => visible.has(id)));
  if (next.size !== selectedIds.value.size) {
    selectedIds.value = next;
  }
});

const startSelection = () => {
  isSelecting.value = true;
  selectedIds.value = new Set();
};

const cancelSelection = () => {
  isSelecting.value = false;
  selectedIds.value = new Set();
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

const toggleAll = () => {
  selectedIds.value = allSelected.value
    ? new Set()
    : new Set(displayedConversations.value.map(c => c.id));
};

const handleExport = async () => {
  if (!hasSelection.value || isExporting.value) return;

  isExporting.value = true;
  try {
    const ids = [...selectedIds.value];
    const { data } = await contactAPI.exportConversations(contactId.value, ids);

    const win = window.open('', '_blank');
    if (!win) {
      useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.POPUP_BLOCKED'));
      return;
    }
    win.document.write(data);
    win.document.close();
    cancelSelection();
  } catch {
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.ERROR'));
  } finally {
    isExporting.value = false;
  }
};
</script>

<template>
  <div
    v-if="isFetching"
    class="flex items-center justify-center py-10 text-n-slate-11"
  >
    <Spinner />
  </div>
  <template v-else>
    <!-- Filtros (admin/supervisor): busca nas mensagens + período -->
    <div
      v-if="canExport && contactConversations.length > 0"
      class="flex flex-col gap-2 px-6 py-2.5 border-b border-n-weak"
    >
      <div class="relative">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-2 top-1/2 size-3.5 text-n-slate-10"
        />
        <input
          v-model="searchQuery"
          type="text"
          :placeholder="
            t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.SEARCH_PLACEHOLDER')
          "
          class="w-full py-1.5 pl-7 pr-7 text-xs border rounded-lg bg-n-alpha-1 border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-woot-500"
        />
        <span
          v-if="isSearching"
          class="absolute -translate-y-1/2 i-lucide-loader-circle animate-spin right-2 top-1/2 size-3.5 text-n-slate-10"
        />
        <button
          v-else-if="searchQuery"
          class="absolute -translate-y-1/2 right-2 top-1/2 text-n-slate-10 hover:text-n-slate-12"
          @click="searchQuery = ''"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
      </div>
      <div class="flex items-center gap-1">
        <button
          v-for="p in periods"
          :key="p.label"
          class="px-2 py-0.5 text-xs transition-colors rounded-full"
          :class="
            periodDays === p.value
              ? 'bg-woot-500 text-white'
              : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="periodDays = p.value"
        >
          {{ p.label }}
        </button>
      </div>
    </div>

    <!-- Barra de ação: exportar ou seleção inline -->
    <div
      v-if="canExport && contactConversations.length > 0"
      class="flex items-center justify-between gap-3 px-6 py-2 border-b border-n-weak min-h-10"
    >
      <template v-if="isSelecting">
        <label
          class="flex items-center gap-2 text-xs font-medium cursor-pointer select-none text-n-slate-11"
        >
          <input
            type="checkbox"
            class="cursor-pointer accent-woot-500 size-3.5"
            :checked="allSelected"
            :indeterminate="hasSelection && !allSelected"
            @change="toggleAll"
          />
          {{
            allSelected
              ? t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.DESELECT_ALL')
              : t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.SELECT_ALL')
          }}
          <span class="font-normal text-n-slate-10">{{ selectionLabel }}</span>
        </label>
        <div class="flex items-center gap-3">
          <button
            class="text-xs font-medium transition-colors text-n-slate-11 hover:text-n-slate-12"
            @click="cancelSelection"
          >
            {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.CANCEL') }}
          </button>
          <button
            class="flex items-center gap-1.5 text-xs font-semibold transition-colors"
            :class="
              hasSelection && !isExporting
                ? 'text-woot-500 hover:text-woot-600'
                : 'text-n-slate-9 cursor-not-allowed'
            "
            :disabled="!hasSelection || isExporting"
            @click="handleExport"
          >
            <span
              v-if="isExporting"
              class="i-lucide-loader-circle animate-spin size-3.5"
            />
            <span v-else class="i-lucide-file-text size-3.5" />
            {{
              isExporting
                ? t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.GENERATING')
                : t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.BUTTON', {
                    count: selectedIds.size,
                  })
            }}
          </button>
        </div>
      </template>
      <template v-else>
        <span />
        <button
          class="flex items-center gap-1.5 text-xs font-medium transition-colors text-n-slate-11 hover:text-woot-500"
          @click="startSelection"
        >
          <span class="i-lucide-file-down size-3.5" />
          {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.TRIGGER_BUTTON') }}
        </button>
      </template>
    </div>

    <div
      v-if="displayedConversations.length > 0"
      class="px-6 divide-y divide-n-strong"
    >
      <div
        v-for="conversation in displayedConversations"
        :key="conversation.id"
        class="flex items-center gap-2"
      >
        <input
          v-if="isSelecting"
          type="checkbox"
          class="cursor-pointer accent-woot-500 size-4 shrink-0"
          :checked="selectedIds.has(conversation.id)"
          @change="toggleConversation(conversation.id)"
        />
        <div class="relative flex-1 min-w-0">
          <ConversationCard
            :conversation="conversation"
            :contact="contactsById(conversation.meta.sender.id)"
            :state-inbox="stateInbox(conversation.inboxId)"
            :account-labels="accountLabelsValue"
            class="rounded-none hover:rounded-xl hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3"
            :class="{ 'pointer-events-none': isSelecting }"
          />
          <!-- Overlay clicável no modo seleção (não navega, só marca) -->
          <div
            v-if="isSelecting"
            class="absolute inset-0 transition-colors cursor-pointer rounded-xl"
            :class="
              selectedIds.has(conversation.id)
                ? 'ring-2 ring-woot-500 bg-woot-500/5'
                : 'hover:bg-n-alpha-1'
            "
            @click="toggleConversation(conversation.id)"
          />
        </div>
      </div>
    </div>
    <p
      v-else-if="contactConversations.length > 0"
      class="px-6 py-10 text-sm leading-6 text-center text-n-slate-11"
    >
      {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.NO_RESULTS') }}
    </p>
    <p v-else class="px-6 py-10 text-sm leading-6 text-center text-n-slate-11">
      {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EMPTY_STATE') }}
    </p>
  </template>
</template>
