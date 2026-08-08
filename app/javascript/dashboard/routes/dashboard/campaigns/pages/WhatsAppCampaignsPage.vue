<script setup>
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useStore,
  useStoreGetters,
  useMapGetter,
} from 'dashboard/composables/store';
import whatsappBulkDispatchAPI from 'dashboard/api/whatsappBulkDispatch';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import WhatsAppCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import WhatsAppCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/WhatsAppCampaignEmptyState.vue';
import BulkDispatchWizard from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/BulkDispatch/BulkDispatchWizard.vue';
import BulkDispatchDetailsDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/BulkDispatch/BulkDispatchDetailsDialog.vue';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const selectedCampaign = ref(null);
const whatsAppCampaignDialogRef = ref(null);
const bulkDispatchWizardRef = ref(null);
const bulkDispatchDetailsDialogRef = ref(null);
// The "+ Criar campanha" button itself is the menu trigger — clicking it doesn't
// open a dialog directly anymore, it reveals which of the two flows to start.
const showCreateMenu = ref(false);

const createMenuItems = computed(() => [
  {
    label: t('CAMPAIGN.WHATSAPP.CREATE_MENU.LABEL_BASED'),
    action: 'newCampaign',
    value: 'newCampaign',
    icon: 'i-lucide-megaphone',
  },
  {
    label: t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.BUTTON_LABEL'),
    action: 'bulkDispatch',
    value: 'bulkDispatch',
    icon: 'i-lucide-sheet',
  },
]);

const handleCreateMenuAction = ({ action }) => {
  showCreateMenu.value = false;
  if (action === 'newCampaign') {
    whatsAppCampaignDialogRef.value?.dialogRef.open();
  } else if (action === 'bulkDispatch') {
    bulkDispatchWizardRef.value?.dialogRef.open();
  }
};

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isFetchingCampaigns = computed(() => uiFlags.value.isFetching);

const confirmDeleteCampaignDialogRef = ref(null);

const nativeCampaigns = computed(
  () => getters['campaigns/getWhatsAppCampaigns'].value
);

// Bulk dispatches aren't Campaign records (see WhatsappBulkDispatch), so they're fetched
// separately here and merged into the same list the operator already sees, instead of
// living in a disconnected section of their own.
const bulkDispatches = ref([]);
const isFetchingBulkDispatches = ref(true);
let bulkDispatchPollTimer = null;

const fetchBulkDispatches = async () => {
  const { data } = await whatsappBulkDispatchAPI.get();
  bulkDispatches.value = data;
  isFetchingBulkDispatches.value = false;

  const hasProcessing = data.some(dispatch => dispatch.status === 'processing');
  if (hasProcessing && !bulkDispatchPollTimer) {
    bulkDispatchPollTimer = setInterval(fetchBulkDispatches, 3000);
  } else if (!hasProcessing && bulkDispatchPollTimer) {
    clearInterval(bulkDispatchPollTimer);
    bulkDispatchPollTimer = null;
  }
};

onMounted(fetchBulkDispatches);
onBeforeUnmount(() => {
  if (bulkDispatchPollTimer) clearInterval(bulkDispatchPollTimer);
});

const isFetching = computed(
  () => isFetchingCampaigns.value || isFetchingBulkDispatches.value
);

// Every file upload in the wizard creates a `draft` record right away, even if the operator
// never confirms it — those never became a real dispatch, so they're left out of the list.
const confirmedDispatches = computed(() =>
  bulkDispatches.value.filter(dispatch => dispatch.status !== 'draft')
);

// Once a campaign/dispatch is fully done, its record is the only proof of what was actually
// sent — deleting it doesn't undo anything, it just destroys that history. So delete stays
// available up to that point (draft/active/processing) and locks once the status is terminal.
const TERMINAL_STATUSES = {
  campaign: ['completed'],
  bulk_dispatch: ['completed', 'failed'],
};

// Shaped exactly like what CampaignList/CampaignCard already expect from a Campaign record
// (snake_case field names included), plus a few extra fields of our own — kind/record — that
// only handleDelete below reads, to tell the two backing resources apart.
const toDisplayItem = (record, kind) => {
  const status = kind === 'campaign' ? record.campaign_status : record.status;

  return {
    id: `${kind}-${record.id}`,
    title: record.title,
    message: record.message,
    enabled: record.enabled ?? true,
    campaign_status: status,
    can_delete: !TERMINAL_STATUSES[kind].includes(status),
    sender: record.sender,
    inbox: record.inbox,
    scheduled_at:
      kind === 'campaign'
        ? record.scheduled_at
        : Math.floor(new Date(record.created_at).getTime() / 1000),
    // Only bulk dispatches need this: their own scheduled_at is nullable (draft/immediate
    // sends never set it) and distinct from scheduled_at above, which always falls back to
    // created_at for the "Enviado de X em Y" row further down — this feeds a separate badge
    // next to the status pill instead, so that row's meaning stays exactly as it was.
    scheduled_for: kind === 'bulk_dispatch' ? record.scheduled_at : null,
    type_label:
      kind === 'campaign'
        ? t('CAMPAIGN.WHATSAPP.CREATE_MENU.LABEL_BASED')
        : t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.BUTTON_LABEL'),
    type_color: kind === 'campaign' ? 'iris' : 'amber',
    created_at: record.created_at,
    kind,
    record,
  };
};

const whatsAppCampaignItems = computed(() =>
  [
    ...nativeCampaigns.value.map(campaign =>
      toDisplayItem(campaign, 'campaign')
    ),
    ...confirmedDispatches.value.map(dispatch =>
      toDisplayItem(dispatch, 'bulk_dispatch')
    ),
  ].sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
);

const hasNoWhatsAppCampaigns = computed(
  () => whatsAppCampaignItems.value.length === 0 && !isFetching.value
);

const kindFilter = ref('all');
const showFilterMenu = ref(false);

const filterMenuItems = computed(() =>
  [
    {
      value: 'all',
      labelKey: 'CAMPAIGN.WHATSAPP.FILTER.ALL',
      icon: 'i-lucide-list',
    },
    {
      value: 'campaign',
      labelKey: 'CAMPAIGN.WHATSAPP.CREATE_MENU.LABEL_BASED',
      icon: 'i-lucide-megaphone',
    },
    {
      value: 'bulk_dispatch',
      labelKey: 'CAMPAIGN.WHATSAPP.BULK_DISPATCH.BUTTON_LABEL',
      icon: 'i-lucide-sheet',
    },
  ].map(item => ({
    ...item,
    label: t(item.labelKey),
    action: item.value,
    isSelected: kindFilter.value === item.value,
  }))
);

const handleFilterAction = ({ action }) => {
  kindFilter.value = action;
  showFilterMenu.value = false;
};

const searchQuery = ref('');

const filteredCampaignItems = computed(() => {
  let items = whatsAppCampaignItems.value;

  if (kindFilter.value !== 'all') {
    items = items.filter(item => item.kind === kindFilter.value);
  }

  const query = searchQuery.value.trim().toLowerCase();
  if (query) {
    items = items.filter(item => item.title?.toLowerCase().includes(query));
  }

  return items;
});

// Distinct from hasNoWhatsAppCampaigns: this is "the filter matched nothing", not
// "there's nothing at all" — the two get different empty states below.
const hasNoFilteredResults = computed(
  () =>
    !isFetching.value &&
    filteredCampaignItems.value.length === 0 &&
    whatsAppCampaignItems.value.length > 0
);

const handleDelete = item => {
  selectedCampaign.value = item;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};

const handleShowDetails = item => {
  bulkDispatchDetailsDialogRef.value?.open(item.record.id);
};

const handleDeleteConfirmed = async item => {
  if (item.kind === 'bulk_dispatch') {
    await whatsappBulkDispatchAPI.delete(item.record.id);
    bulkDispatches.value = bulkDispatches.value.filter(
      dispatch => dispatch.id !== item.record.id
    );
  } else {
    await store.dispatch('campaigns/delete', item.record.id);
  }
};
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.WHATSAPP.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.WHATSAPP.NEW_CAMPAIGN')"
    @click="showCreateMenu = !showCreateMenu"
    @close="showCreateMenu = false"
  >
    <template #filter>
      <template v-if="!isFetching && !hasNoWhatsAppCampaigns">
        <Input
          v-model="searchQuery"
          type="search"
          :placeholder="t('CAMPAIGN.WHATSAPP.SEARCH_PLACEHOLDER')"
          :custom-input-class="[
            'h-8 [&:not(.focus)]:!border-transparent bg-n-alpha-2 dark:bg-n-solid-1 ltr:!pl-8 !py-1 rtl:!pr-8',
          ]"
          class="w-48"
        >
          <template #prefix>
            <Icon
              icon="i-lucide-search"
              class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
            />
          </template>
        </Input>
        <div
          v-on-click-outside="() => (showFilterMenu = false)"
          class="relative"
        >
          <Button
            icon="i-lucide-list-filter"
            variant="faded"
            color="slate"
            size="sm"
            @click="showFilterMenu = !showFilterMenu"
          />
          <DropdownMenu
            v-if="showFilterMenu"
            :menu-items="filterMenuItems"
            class="ltr:right-0 rtl:left-0 mt-1 w-56 top-full"
            @action="handleFilterAction"
          />
        </div>
      </template>
    </template>
    <template #action>
      <DropdownMenu
        v-if="showCreateMenu"
        :menu-items="createMenuItems"
        class="ltr:right-0 rtl:left-0 mt-1 w-56 top-full"
        @action="handleCreateMenuAction"
      />
    </template>
    <div
      v-if="isFetching"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>
    <CampaignList
      v-else-if="!hasNoWhatsAppCampaigns && !hasNoFilteredResults"
      :campaigns="filteredCampaignItems"
      @delete="handleDelete"
      @details="handleShowDetails"
    />
    <p
      v-else-if="hasNoFilteredResults"
      class="pt-14 text-sm text-center text-n-slate-11"
    >
      {{ t('CAMPAIGN.WHATSAPP.FILTER.NO_RESULTS') }}
    </p>
    <WhatsAppCampaignEmptyState
      v-else
      :title="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.TITLE')"
      :subtitle="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.SUBTITLE')"
      class="pt-14"
    />
    <ConfirmDeleteCampaignDialog
      ref="confirmDeleteCampaignDialogRef"
      :selected-campaign="selectedCampaign"
      :delete-handler="handleDeleteConfirmed"
    />
    <WhatsAppCampaignDialog ref="whatsAppCampaignDialogRef" />
    <BulkDispatchWizard
      ref="bulkDispatchWizardRef"
      @close="fetchBulkDispatches"
    />
    <BulkDispatchDetailsDialog ref="bulkDispatchDetailsDialogRef" />
  </CampaignLayout>
</template>
