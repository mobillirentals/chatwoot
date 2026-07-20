<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert, useTrack } from 'dashboard/composables';
import { CAMPAIGN_TYPES } from 'shared/constants/campaign.js';
import { CAMPAIGNS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events.js';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import WhatsAppCampaignForm from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignForm.vue';

const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const formRef = ref(null);
const savedFormState = ref(null);
let isDeliberateClose = false;

const addCampaign = async campaignDetails => {
  try {
    await store.dispatch('campaigns/create', campaignDetails);

    useTrack(CAMPAIGNS_EVENTS.CREATE_CAMPAIGN, {
      type: CAMPAIGN_TYPES.ONE_OFF,
    });

    useAlert(t('CAMPAIGN.WHATSAPP.CREATE.FORM.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.response?.message ||
      t('CAMPAIGN.WHATSAPP.CREATE.FORM.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const handleSubmit = campaignDetails => {
  addCampaign(campaignDetails);
};

// Bound to Dialog's own @close (fires on Esc, click-outside, or our requestClose()
// below — Dialog's close() emits this itself). Must not call dialogRef.close() here:
// see BulkDispatchWizard.vue, which hit the infinite-loop version of this mistake.
//
// Also snapshots whatever's currently in the form before Dialog's v-if unmounts it — an
// accidental outside-click/Esc shouldn't throw away in-progress typing. Skipped when the close
// was deliberate (requestClose already cleared the snapshot itself, right below).
const handleClose = () => {
  if (!isDeliberateClose && formRef.value) {
    savedFormState.value = { ...formRef.value.state };
  }
  isDeliberateClose = false;
  emit('close');
};

// Bound to the form's own Cancel button and to its post-submit auto-cancel (both via
// @cancel) — Dialog's built-in buttons are off, so this is what actually closes it. A
// deliberate exit, so the saved snapshot is cleared before Dialog's own @close (handleClose
// above) would otherwise re-capture it.
const requestClose = () => {
  isDeliberateClose = true;
  savedFormState.value = null;
  dialogRef.value?.close();
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="lg"
    :title="t('CAMPAIGN.WHATSAPP.CREATE.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <WhatsAppCampaignForm
      ref="formRef"
      :initial-state="savedFormState"
      @submit="handleSubmit"
      @cancel="requestClose"
    />
  </Dialog>
</template>
