<script setup>
import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import contactAPI from 'dashboard/api/contacts';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationCard from 'dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue';
import ConversationPreviewModal from 'dashboard/components-next/Contacts/ContactsSidebar/ConversationPreviewModal.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

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

// ── Filtro de período manual (client-side) ───────────────────────────────
const dateFrom = ref(''); // 'YYYY-MM-DD'
const dateTo = ref('');

const clearPeriod = () => {
  dateFrom.value = '';
  dateTo.value = '';
};

const displayedConversations = computed(() => {
  let list = contactConversations.value;

  const fromTs = dateFrom.value
    ? new Date(`${dateFrom.value}T00:00:00`).getTime() / 1000
    : null;
  const toTs = dateTo.value
    ? new Date(`${dateTo.value}T23:59:59`).getTime() / 1000
    : null;

  if (fromTs || toTs) {
    list = list.filter(c => {
      const ts = c.last_activity_at || c.created_at || 0;
      if (fromTs && ts < fromTs) return false;
      if (toTs && ts > toTs) return false;
      return true;
    });
  }

  return list;
});

// ── Busca nas mensagens (backend) — estilo WhatsApp ───────────────────────
const searchQuery = ref('');
const searchResults = ref([]); // mensagens que casaram
const isSearching = ref(false);
const hasActiveSearch = computed(() => searchQuery.value.trim().length > 0);

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
    searchResults.value = data.messages || [];
  } catch (error) {
    if (error?.code === 'ERR_CANCELED' || error?.name === 'CanceledError') {
      return;
    }
    searchResults.value = [];
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
    searchResults.value = [];
    isSearching.value = false;
    return;
  }
  isSearching.value = true;
  searchTimer = setTimeout(() => runSearch(query), 350);
});

const searchTime = createdAt => (createdAt ? dynamicTime(createdAt) : '');

const { highlightContent } = useMessageFormatter();

// Realça o termo buscado no snippet (reusa o helper nativo da plataforma).
const highlightedSnippet = content =>
  highlightContent(content, searchQuery.value.trim(), 'searchkey--highlight');

// "Pular pra mensagem": abre a conversa real já rolando até a mensagem.
const jumpToMessage = result => {
  if (!result.conversation_id || !result.message_id) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: result.conversation_id,
    },
    query: { messageId: result.message_id },
  });
};

// ── Seleção inline para exportação em PDF ─────────────────────────
const isSelecting = ref(false);
const selectedIds = ref(new Set());
const isExporting = ref(false);

// ── Prévia da conversa (popup — lê sem sair da tela nem perder a seleção) ──
const previewConvId = ref(null);
const openPreview = conversation => {
  previewConvId.value = conversation.id;
};
const closePreview = () => {
  previewConvId.value = null;
};

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
        <span class="absolute i-lucide-search size-3.5 top-2 left-3" />
        <input
          v-model="searchQuery"
          type="search"
          :placeholder="
            t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.SEARCH_PLACEHOLDER')
          "
          class="w-full h-8 py-2 pl-10 pr-8 text-sm border-none rounded-lg outline-none reset-base bg-n-alpha-black2 dark:bg-n-solid-1 text-n-slate-12"
        />
        <span
          v-if="isSearching"
          class="absolute i-lucide-loader-circle animate-spin size-3.5 top-2 right-3 text-n-slate-10"
        />
      </div>
      <div v-if="!hasActiveSearch" class="flex items-end gap-2">
        <Input
          v-model="dateFrom"
          type="date"
          size="sm"
          :label="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.PERIOD_FROM')"
          :max="dateTo"
          class="flex-1 min-w-0"
        />
        <Input
          v-model="dateTo"
          type="date"
          size="sm"
          :label="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.PERIOD_TO')"
          :min="dateFrom"
          class="flex-1 min-w-0"
        />
        <button
          v-if="dateFrom || dateTo"
          type="button"
          class="flex items-center justify-center h-8 transition-colors shrink-0 text-n-slate-10 hover:text-n-slate-12"
          :aria-label="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.FILTER.PERIOD_CLEAR')"
          @click="clearPeriod"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>
    </div>

    <!-- Resultados da busca (estilo WhatsApp): clicar pula pra mensagem -->
    <template v-if="hasActiveSearch">
      <div
        v-if="isSearching && searchResults.length === 0"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>
      <div v-else-if="searchResults.length > 0" class="flex flex-col px-3 py-2">
        <button
          v-for="result in searchResults"
          :key="result.message_id"
          type="button"
          class="flex flex-col gap-1 px-3 py-2.5 text-left transition-colors rounded-lg cursor-pointer hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3"
          @click="jumpToMessage(result)"
        >
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center min-w-0 gap-1.5 text-n-slate-11">
              <span class="i-lucide-hash size-3.5 shrink-0" />
              <span class="text-xs font-medium truncate">
                {{
                  result.sender_name
                    ? `${result.conversation_id} · ${result.sender_name}`
                    : `${result.conversation_id}`
                }}
              </span>
            </div>
            <span class="text-xs shrink-0 text-n-slate-10">
              {{ searchTime(result.created_at) }}
            </span>
          </div>
          <p
            class="text-sm leading-5 text-n-slate-12 line-clamp-2 [&_.searchkey--highlight]:font-semibold [&_.searchkey--highlight]:text-woot-500"
          >
            <span v-if="result.private" class="font-medium text-n-amber-11">
              {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.SEARCH_RESULTS.PRIVATE') }}
            </span>
            <span v-dompurify-html="highlightedSnippet(result.content)" />
          </p>
        </button>
      </div>
      <p
        v-else
        class="px-6 py-10 text-sm leading-6 text-center text-n-slate-11"
      >
        {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.SEARCH_RESULTS.EMPTY') }}
      </p>
    </template>

    <!-- Barra de ação: exportar ou seleção inline -->
    <div
      v-if="!hasActiveSearch && canExport && contactConversations.length > 0"
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

    <template v-if="!hasActiveSearch">
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
          <div
            class="relative flex-1 min-w-0 rounded-xl"
            :class="{
              'ring-2 ring-inset ring-woot-500':
                isSelecting && selectedIds.has(conversation.id),
            }"
          >
            <ConversationCard
              :conversation="conversation"
              :contact="contactsById(conversation.meta.sender.id)"
              :state-inbox="stateInbox(conversation.inboxId)"
              :account-labels="accountLabelsValue"
              class="rounded-none hover:rounded-xl hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3"
              :class="{ 'pointer-events-none': isSelecting }"
            />
            <!-- No modo seleção: clicar no card abre a prévia (não navega); só o checkbox seleciona -->
            <button
              v-if="isSelecting"
              type="button"
              class="absolute inset-0 transition-colors cursor-pointer rounded-xl hover:bg-n-alpha-1"
              :aria-label="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PREVIEW.OPEN')"
              @click="openPreview(conversation)"
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
      <p
        v-else
        class="px-6 py-10 text-sm leading-6 text-center text-n-slate-11"
      >
        {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EMPTY_STATE') }}
      </p>
    </template>

    <ConversationPreviewModal
      v-if="previewConvId"
      :conversation-id="previewConvId"
      @close="closePreview"
    />
  </template>
</template>
