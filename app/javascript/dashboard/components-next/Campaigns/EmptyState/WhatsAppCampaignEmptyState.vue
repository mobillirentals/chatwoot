<script setup>
import { useI18n } from 'vue-i18n';
import { ONE_OFF_CAMPAIGN_EMPTY_STATE_CONTENT } from './CampaignEmptyStateContent';

import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import CampaignCard from 'dashboard/components-next/Campaigns/CampaignCard/CampaignCard.vue';

defineProps({
  title: {
    type: String,
    default: '',
  },
  subtitle: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
</script>

<template>
  <EmptyStateLayout :title="title" :subtitle="subtitle">
    <template #empty-state-item>
      <div class="flex flex-col gap-4 p-px">
        <CampaignCard
          v-for="campaign in ONE_OFF_CAMPAIGN_EMPTY_STATE_CONTENT"
          :key="campaign.id"
          :title="campaign.title"
          :message="campaign.message"
          :is-enabled="campaign.enabled"
          :status="campaign.campaign_status"
          :sender="campaign.sender"
          :inbox="campaign.inbox"
          :scheduled-at="campaign.scheduled_at"
          :type-label="t('CAMPAIGN.WHATSAPP.CREATE_MENU.LABEL_BASED')"
          type-color="iris"
        />
      </div>
    </template>
  </EmptyStateLayout>
</template>
