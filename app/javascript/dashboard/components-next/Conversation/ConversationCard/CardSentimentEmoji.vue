<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { SENTIMENT_LEVELS } from 'shared/constants/messages';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const props = defineProps({
  sentiment: {
    type: Number,
    default: null,
  },
});

const { t } = useI18n();
const { isCloudFeatureEnabled } = useAccount();

// The API already omits the field when Captain is off, so this is a second lock: it also
// covers conversations still held in the store from before the feature was turned off.
const level = computed(() => {
  if (!isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN)) return null;
  return SENTIMENT_LEVELS.find(item => item.value === props.sentiment) ?? null;
});

const label = computed(() =>
  level.value ? t(level.value.translationKey) : ''
);
</script>

<template>
  <span
    v-if="level"
    v-tooltip.top="{ content: label, delay: { show: 500, hide: 0 } }"
    class="text-sm leading-none shrink-0"
    :aria-label="label"
  >
    {{ level.emoji }}
  </span>
  <!-- `hidden` keeps the empty placeholder out of the flex flow, so the parent's gap does
       not shift the contact name on conversations that have no sentiment yet. -->
  <span v-else class="hidden" />
</template>
