<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageStamp } from 'shared/helpers/timeHelper';
import whatsappBulkDispatchAPI from 'dashboard/api/whatsappBulkDispatch';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const dialogRef = ref(null);
const isLoading = ref(false);
const details = ref(null);
const statusFilter = ref('all');
let pollTimer = null;

const STATUS_BADGE_COLOR = {
  sent: 'text-n-teal-11',
  failed: 'text-n-ruby-11',
  pending: 'text-n-amber-11',
};

// Recipients only carry the template's raw variable positions ("1", "2", ...) — column_mapping
// on the same response is what says "1" was fed by the spreadsheet's "nome" column, so the
// table can show that instead of bare numbers.
const variableLabels = computed(() => {
  const mapping = details.value?.column_mapping || {};
  return Object.fromEntries(
    Object.entries(mapping).filter(([key]) => key !== '__phone__')
  );
});

const formatVariables = variables =>
  Object.entries(variables || {})
    .map(([key, value]) => `${variableLabels.value[key] || key}: ${value}`)
    .join(' · ');

const recipients = computed(() => details.value?.recipients || []);

const countByStatus = status =>
  recipients.value.filter(recipient => recipient.status === status).length;

const statusFilters = computed(() => [
  {
    value: 'all',
    label: t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.DETAILS.FILTERS.ALL'),
    count: recipients.value.length,
  },
  {
    value: 'sent',
    label: t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.DETAILS.FILTERS.SENT'),
    count: countByStatus('sent'),
  },
  {
    value: 'failed',
    label: t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.DETAILS.FILTERS.FAILED'),
    count: countByStatus('failed'),
  },
  {
    value: 'pending',
    label: t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.DETAILS.FILTERS.PENDING'),
    count: countByStatus('pending'),
  },
]);

const filteredRecipients = computed(() => {
  if (statusFilter.value === 'all') return recipients.value;
  return recipients.value.filter(
    recipient => recipient.status === statusFilter.value
  );
});

const totalRecipients = computed(() => details.value?.total_recipients || 0);
const sentPercent = computed(() =>
  totalRecipients.value
    ? Math.round((details.value.sent_count / totalRecipients.value) * 100)
    : 0
);
const failedPercent = computed(() =>
  totalRecipients.value
    ? Math.round((details.value.failed_count / totalRecipients.value) * 100)
    : 0
);

const formatSentAt = sentAt =>
  sentAt ? messageStamp(new Date(sentAt), 'LLL d, h:mm a') : '—';

const fetchDetails = async id => {
  const { data } = await whatsappBulkDispatchAPI.show(id);
  details.value = data;

  if (data.status === 'processing' && !pollTimer) {
    pollTimer = setInterval(() => fetchDetails(id), 3000);
  } else if (data.status !== 'processing' && pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

const open = async id => {
  statusFilter.value = 'all';
  details.value = null;
  isLoading.value = true;
  dialogRef.value?.open();
  try {
    await fetchDetails(id);
  } finally {
    isLoading.value = false;
  }
};

// Bound to Dialog's own @close — cleanup only, never calls dialogRef.close() again (that's
// exactly what would trigger this handler in the first place).
const handleClose = () => {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
  details.value = null;
};

const requestClose = () => dialogRef.value?.close();

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="details?.title"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <div
      v-if="isLoading && !details"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>
    <div v-else-if="details" class="flex flex-col gap-4">
      <div class="grid grid-cols-3 gap-3">
        <div class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-2">
          <span class="text-xs text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.DETAILS.TOTAL') }}
          </span>
          <span class="text-xl font-semibold tabular-nums text-n-slate-12">
            {{ totalRecipients }}
          </span>
        </div>
        <div class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-2">
          <span class="text-xs text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.DETAILS.SENT') }}
          </span>
          <span class="text-xl font-semibold tabular-nums text-n-teal-11">
            {{ details.sent_count }}
          </span>
        </div>
        <div class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-2">
          <span class="text-xs text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.DETAILS.FAILED') }}
          </span>
          <span class="text-xl font-semibold tabular-nums text-n-ruby-11">
            {{ details.failed_count }}
          </span>
        </div>
      </div>

      <div class="flex w-full h-2 overflow-hidden rounded-full bg-n-alpha-2">
        <div class="h-full bg-n-teal-9" :style="{ width: `${sentPercent}%` }" />
        <div
          class="h-full bg-n-ruby-9"
          :style="{ width: `${failedPercent}%` }"
        />
      </div>

      <div class="flex items-center gap-2">
        <button
          v-for="filter in statusFilters"
          :key="filter.value"
          type="button"
          class="px-2.5 py-1 text-xs font-medium rounded-md"
          :class="
            statusFilter === filter.value
              ? 'bg-n-solid-blue text-white'
              : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'
          "
          @click="statusFilter = filter.value"
        >
          {{ filter.label }} ({{ filter.count }})
        </button>
      </div>

      <div
        class="flex flex-col overflow-y-auto rounded-lg max-h-80 bg-n-solid-2"
      >
        <div
          v-for="recipient in filteredRecipients"
          :key="recipient.id"
          class="flex flex-col gap-1 px-3 py-2 border-b border-n-weak last:border-b-0"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ recipient.phone_number }}
            </span>
            <div class="flex items-center gap-2">
              <span class="text-xs text-n-slate-11">
                {{ formatSentAt(recipient.sent_at) }}
              </span>
              <span
                class="text-xs font-medium capitalize"
                :class="STATUS_BADGE_COLOR[recipient.status]"
              >
                {{
                  t(
                    `CAMPAIGN.WHATSAPP.BULK_DISPATCH.DETAILS.FILTERS.${recipient.status.toUpperCase()}`
                  )
                }}
              </span>
            </div>
          </div>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ formatVariables(recipient.variables) }}
          </p>
          <p v-if="recipient.error_message" class="mb-0 text-xs text-n-ruby-11">
            {{ recipient.error_message }}
          </p>
        </div>
        <p
          v-if="!filteredRecipients.length"
          class="py-6 text-sm text-center text-n-slate-11"
        >
          {{ t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.DETAILS.EMPTY') }}
        </p>
      </div>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <a
          v-if="details?.failed_rows_url"
          :href="details.failed_rows_url"
          target="_blank"
          rel="noopener noreferrer"
          class="text-sm text-n-blue-11"
        >
          {{ t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.REPORT.DOWNLOAD_REJECTED') }}
        </a>
        <span v-else />
        <Button
          variant="faded"
          color="slate"
          type="button"
          :label="t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.NAVIGATION.CLOSE')"
          class="!w-fit"
          @click="requestClose"
        />
      </div>
    </template>
  </Dialog>
</template>
