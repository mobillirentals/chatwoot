<script setup>
import { ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  selectedCampaign: {
    type: Object,
    default: null,
  },
  // Only set on the WhatsApp page, where the list mixes real Campaign records with
  // WhatsappBulkDispatch ones — those delete through a different API entirely. Left null
  // everywhere else, which keeps the default store dispatch below as-is.
  deleteHandler: {
    type: Function,
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);

const deleteCampaign = async campaign => {
  if (!campaign) return;

  try {
    if (props.deleteHandler) {
      await props.deleteHandler(campaign);
    } else {
      await store.dispatch('campaigns/delete', campaign.id);
    }
    useAlert(t('CAMPAIGN.CONFIRM_DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('CAMPAIGN.CONFIRM_DELETE.API.ERROR_MESSAGE'));
  }
};

const handleDialogConfirm = async () => {
  await deleteCampaign(props.selectedCampaign);
  dialogRef.value?.close();
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('CAMPAIGN.CONFIRM_DELETE.TITLE')"
    :description="t('CAMPAIGN.CONFIRM_DELETE.DESCRIPTION')"
    :confirm-button-label="t('CAMPAIGN.CONFIRM_DELETE.CONFIRM')"
    @confirm="handleDialogConfirm"
  />
</template>
