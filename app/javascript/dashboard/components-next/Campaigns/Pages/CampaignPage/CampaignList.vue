<script setup>
import CampaignCard from 'dashboard/components-next/Campaigns/CampaignCard/CampaignCard.vue';

defineProps({
  campaigns: {
    type: Array,
    required: true,
  },
  isLiveChatType: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['edit', 'delete', 'details']);

const handleEdit = campaign => emit('edit', campaign);
const handleDelete = campaign => emit('delete', campaign);
const handleDetails = campaign => emit('details', campaign);
</script>

<template>
  <div class="flex flex-col gap-4">
    <CampaignCard
      v-for="campaign in campaigns"
      :key="campaign.id"
      :title="campaign.title"
      :message="campaign.message"
      :is-enabled="campaign.enabled"
      :status="campaign.campaign_status"
      :sender="campaign.sender"
      :inbox="campaign.inbox"
      :scheduled-at="campaign.scheduled_at"
      :is-live-chat-type="isLiveChatType"
      :type-label="campaign.type_label"
      :type-color="campaign.type_color"
      :show-details-button="campaign.kind === 'bulk_dispatch'"
      :can-delete="campaign.can_delete"
      @edit="handleEdit(campaign)"
      @delete="handleDelete(campaign)"
      @details="handleDetails(campaign)"
    />
  </div>
</template>
