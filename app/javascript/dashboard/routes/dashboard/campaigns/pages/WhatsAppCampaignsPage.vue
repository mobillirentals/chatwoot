<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useMapGetter } from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import WhatsAppCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import WhatsAppCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/WhatsAppCampaignEmptyState.vue';
import BulkDispatchWizard from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/BulkDispatch/BulkDispatchWizard.vue';

const { t } = useI18n();
const getters = useStoreGetters();

const selectedCampaign = ref(null);
const whatsAppCampaignDialogRef = ref(null);
const bulkDispatchWizardRef = ref(null);
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

const WhatsAppCampaigns = computed(
  () => getters['campaigns/getWhatsAppCampaigns'].value
);

const hasNoWhatsAppCampaigns = computed(
  () => WhatsAppCampaigns.value?.length === 0 && !isFetchingCampaigns.value
);

const handleDelete = campaign => {
  selectedCampaign.value = campaign;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.WHATSAPP.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.WHATSAPP.NEW_CAMPAIGN')"
    @click="showCreateMenu = !showCreateMenu"
    @close="showCreateMenu = false"
  >
    <template #action>
      <DropdownMenu
        v-if="showCreateMenu"
        :menu-items="createMenuItems"
        class="ltr:right-0 rtl:left-0 mt-1 w-56 top-full"
        @action="handleCreateMenuAction"
      />
    </template>
    <div
      v-if="isFetchingCampaigns"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>
    <CampaignList
      v-else-if="!hasNoWhatsAppCampaigns"
      :campaigns="WhatsAppCampaigns"
      @delete="handleDelete"
    />
    <WhatsAppCampaignEmptyState
      v-else
      :title="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.TITLE')"
      :subtitle="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.SUBTITLE')"
      class="pt-14"
    />
    <ConfirmDeleteCampaignDialog
      ref="confirmDeleteCampaignDialogRef"
      :selected-campaign="selectedCampaign"
    />
    <WhatsAppCampaignDialog ref="whatsAppCampaignDialogRef" />
    <BulkDispatchWizard ref="bulkDispatchWizardRef" />
  </CampaignLayout>
</template>
