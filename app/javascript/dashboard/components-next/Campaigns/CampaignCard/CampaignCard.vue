<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import { messageStamp } from 'shared/helpers/timeHelper';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import LiveChatCampaignDetails from './LiveChatCampaignDetails.vue';
import SMSCampaignDetails from './SMSCampaignDetails.vue';

const props = defineProps({
  title: {
    type: String,
    default: '',
  },
  message: {
    type: String,
    default: '',
  },
  isLiveChatType: {
    type: Boolean,
    default: false,
  },
  isEnabled: {
    type: Boolean,
    default: false,
  },
  status: {
    type: String,
    default: '',
  },
  sender: {
    type: Object,
    default: null,
  },
  inbox: {
    type: Object,
    default: null,
  },
  scheduledAt: {
    type: Number,
    default: 0,
  },
  // Only set for a bulk dispatch that's actually scheduled for the future (draft/immediate
  // sends leave this null) — drives a small badge next to the status pill, kept separate from
  // scheduledAt above so that field's own meaning (used in the row further down) stays untouched.
  scheduledFor: {
    type: Number,
    default: null,
  },
  // Only set on the WhatsApp page, where label-based campaigns and spreadsheet bulk dispatches
  // now share one list — the tag is what tells the two apart at a glance. Left blank (the
  // default) on SMS/live-chat cards, which only ever have one kind of item.
  typeLabel: {
    type: String,
    default: '',
  },
  typeColor: {
    type: String,
    default: 'slate',
  },
  // Only bulk dispatches have a recipient-by-recipient breakdown worth a dedicated view —
  // label-based campaigns don't track individual sends the same way.
  showDetailsButton: {
    type: Boolean,
    default: false,
  },
  // A completed campaign's record is the only proof of what was actually sent — deleting it
  // doesn't undo the send, it just destroys that history. Defaults to true so SMS/live-chat
  // cards (which never pass this prop) keep behaving exactly as before.
  canDelete: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['edit', 'delete', 'details']);

const { t } = useI18n();

const STATUS_COMPLETED = 'completed';
const STATUS_PROCESSING = 'processing';
const STATUS_FAILED = 'failed';

const { formatMessage } = useMessageFormatter();

const statusTextColor = computed(() => {
  if (props.status === STATUS_FAILED) return 'text-n-ruby-11';
  if (!props.isLiveChatType && props.status === STATUS_COMPLETED) {
    return 'text-n-slate-12';
  }
  return props.isLiveChatType && !props.isEnabled
    ? 'text-n-slate-12'
    : 'text-n-teal-11';
});

const campaignStatus = computed(() => {
  if (props.isLiveChatType) {
    return props.isEnabled
      ? t('CAMPAIGN.LIVE_CHAT.CARD.STATUS.ENABLED')
      : t('CAMPAIGN.LIVE_CHAT.CARD.STATUS.DISABLED');
  }

  if (props.status === STATUS_COMPLETED) {
    return t('CAMPAIGN.SMS.CARD.STATUS.COMPLETED');
  }

  if (props.status === STATUS_PROCESSING) {
    return t('CAMPAIGN.SMS.CARD.STATUS.PROCESSING');
  }

  if (props.status === STATUS_FAILED) {
    return t('CAMPAIGN.SMS.CARD.STATUS.FAILED');
  }

  return t('CAMPAIGN.SMS.CARD.STATUS.SCHEDULED');
});

const formattedScheduledFor = computed(() => {
  if (!props.scheduledFor) return '';
  // Matches SMSCampaignDetails' own scheduledAt handling just below: messageStamp expects unix
  // seconds and multiplies by 1000 itself, so wrap in `new Date` without doing that here too.
  return messageStamp(new Date(props.scheduledFor), 'LLL d, h:mm a');
});

const inboxName = computed(() => props.inbox?.name || '');

const inboxIcon = computed(() => {
  const {
    medium,
    channel_type: type,
    voice_enabled: voiceEnabled,
  } = props.inbox;
  return getInboxIconByType(type, medium, 'fill', voiceEnabled);
});
</script>

<template>
  <CardLayout layout="row">
    <div class="flex flex-col items-start justify-between flex-1 min-w-0 gap-2">
      <div class="flex justify-between gap-3 w-fit">
        <span
          class="text-base font-medium capitalize text-n-slate-12 line-clamp-1"
        >
          {{ title }}
        </span>
        <span
          class="text-xs font-medium inline-flex items-center h-6 px-2 py-0.5 rounded-md bg-n-alpha-2"
          :class="statusTextColor"
        >
          {{ campaignStatus }}
        </span>
        <Label
          v-if="formattedScheduledFor"
          :label="formattedScheduledFor"
          color="teal"
          compact
        >
          <template #icon>
            <Icon icon="i-lucide-calendar-clock" class="size-3.5" />
          </template>
        </Label>
        <Label v-if="typeLabel" :label="typeLabel" :color="typeColor" compact />
      </div>
      <div
        v-dompurify-html="formatMessage(message, false, false, false)"
        class="text-sm text-n-slate-11 line-clamp-1 [&>p]:mb-0 h-6"
      />
      <div class="flex items-center w-full h-6 gap-2 overflow-hidden">
        <LiveChatCampaignDetails
          v-if="isLiveChatType"
          :sender="sender"
          :inbox-name="inboxName"
          :inbox-icon="inboxIcon"
        />
        <SMSCampaignDetails
          v-else
          :sender="sender"
          :inbox-name="inboxName"
          :inbox-icon="inboxIcon"
          :scheduled-at="scheduledAt"
        />
      </div>
    </div>
    <div class="flex items-center justify-end gap-2 w-fit">
      <Button
        v-if="isLiveChatType"
        variant="faded"
        size="sm"
        color="slate"
        icon="i-lucide-sliders-vertical"
        @click="emit('edit')"
      />
      <Button
        v-if="showDetailsButton"
        variant="faded"
        size="sm"
        color="slate"
        icon="i-lucide-bar-chart-3"
        @click="emit('details')"
      />
      <Button
        v-tooltip.top="
          canDelete ? null : t('CAMPAIGN.CARD.DELETE_DISABLED_TOOLTIP')
        "
        variant="faded"
        color="ruby"
        size="sm"
        icon="i-lucide-trash"
        :disabled="!canDelete"
        @click="emit('delete')"
      />
    </div>
  </CardLayout>
</template>
