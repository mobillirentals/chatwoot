<script setup>
import { reactive, computed, ref, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { messageStamp } from 'shared/helpers/timeHelper';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import whatsappBulkDispatchAPI from 'dashboard/api/whatsappBulkDispatch';

const emit = defineEmits(['close']);
const { t } = useI18n();
const store = useStore();

const STEPS = {
  TEMPLATE: 1,
  UPLOAD: 2,
  MAPPING: 3,
  REVIEW: 4,
  CONFIRM: 5,
  REPORT: 6,
};

const step = ref(STEPS.TEMPLATE);
const isSubmitting = ref(false);
const dialogRef = ref(null);
const fileInput = ref(null);

const inboxes = useMapGetter('inboxes/getWhatsAppInboxes');
const getFilteredWhatsAppTemplates = useMapGetter(
  'inboxes/getFilteredWhatsAppTemplates'
);

const form = reactive({
  title: '',
  inboxId: null,
  templateId: null,
});

const selectedFile = ref(null);
const dispatchId = ref(null);
const headers = ref([]);
const columnMapping = reactive({});
const PHONE_KEY = '__phone__';

const validation = ref(null);
// confirmed+notFound (nao inclui unchecked) — total de numeros que o servico de verificacao
// de fato respondeu; 0 quando o servico esta fora do ar/nao configurado, escondendo a linha.
const whatsappCheckTotal = computed(() => {
  const check = validation.value?.whatsappCheck;
  return check ? check.confirmed + check.not_found : 0;
});
const sendMode = ref('now');
const scheduledAt = ref(null);
const showSendModeMenu = ref(false);

// Same split-button shape as ArticleEditorHeader.vue's publish/draft menu — the chevron just
// switches which mode is selected, the primary button (in the template) is what actually sends.
const sendModeMenuItems = computed(() => [
  {
    value: 'now',
    action: 'now',
    icon: 'i-lucide-send',
    label: t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.SEND_NOW'),
    isSelected: sendMode.value === 'now',
  },
  {
    value: 'scheduled',
    action: 'scheduled',
    icon: 'i-lucide-calendar-clock',
    label: t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.SCHEDULE'),
    isSelected: sendMode.value === 'scheduled',
  },
]);

const handleSendModeAction = ({ action }) => {
  sendMode.value = action;
  showSendModeMenu.value = false;
};
const reportState = reactive({
  status: 'draft',
  totalRecipients: 0,
  sentCount: 0,
  failedCount: 0,
  failedRowsUrl: null,
  scheduledAt: null,
});
let pollTimer = null;

// Same pattern as WhatsAppCampaignForm.vue's scheduled-at field — disables picking a time
// that's already in the past.
const currentDateTime = computed(() => {
  const now = new Date();
  const localTime = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return localTime.toISOString().slice(0, 16);
});

const scheduledCampaignInterval = computed(
  () => store.getters['globalConfig/get'].scheduledCampaignInterval || 5
);

const mapToOptions = (items, valueKey, labelKey) =>
  items?.map(item => ({ value: item[valueKey], label: item[labelKey] })) ?? [];

const inboxOptions = computed(() => mapToOptions(inboxes.value, 'id', 'name'));

const templateOptions = computed(() => {
  if (!form.inboxId) return [];
  return getFilteredWhatsAppTemplates.value(form.inboxId).map(template => ({
    value: template.id,
    label: `${template.name} (${template.language || 'en'})`,
    template,
  }));
});

const selectedTemplate = computed(() => {
  if (!form.templateId) return null;
  return templateOptions.value.find(option => option.value === form.templateId)
    ?.template;
});

// Every real approved template on this account is POSITIONAL ({{1}}, {{2}}, ...) rather than
// named — variable identity is derived straight from the body text, the same numeric-string
// convention WhatsappBulkDispatch#variable_names uses on the backend.
const templateVariableNames = computed(() => {
  const template = selectedTemplate.value;
  if (!template) return [];

  const body = template.components?.find(c => c.type === 'BODY');
  const matches = [...(body?.text || '').matchAll(/\{\{\s*(\d+)\s*\}\}/g)];
  const numbers = [...new Set(matches.map(match => match[1]))];
  return numbers.sort((a, b) => Number(a) - Number(b));
});

const templateBodyText = computed(() => {
  const body = selectedTemplate.value?.components?.find(c => c.type === 'BODY');
  return body?.text || '';
});

// Column names match the "telefone" / "variavel_N" hints ColumnMapperService already looks
// for, so uploading the file back auto-suggests the mapping in the next step. Built as a real
// .xlsx on the backend (via caxlsx) — operators here default to Excel, and a CSV renamed to
// .xlsx would just show as a corrupt-file warning when opened.
const downloadTemplateSpreadsheet = async () => {
  const template = selectedTemplate.value;
  if (!template) return;

  const { data } = await whatsappBulkDispatchAPI.templateSpreadsheet(
    templateVariableNames.value
  );
  const url = URL.createObjectURL(data);
  const link = document.createElement('a');
  link.href = url;
  link.download = `modelo-${template.name}.xlsx`;
  link.click();
  URL.revokeObjectURL(url);
};

const columnOptions = computed(() =>
  headers.value.map(header => ({ value: header, label: header }))
);

const isTemplateStepValid = computed(
  () => form.title && form.inboxId && form.templateId
);

const isMappingStepValid = computed(() => {
  if (!columnMapping[PHONE_KEY]) return false;
  return templateVariableNames.value.every(name => columnMapping[name]);
});

const STEP_TITLE_KEYS = {
  [STEPS.TEMPLATE]: 'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.TEMPLATE.TITLE',
  [STEPS.UPLOAD]: 'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.UPLOAD.TITLE',
  [STEPS.MAPPING]: 'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.MAPPING.TITLE',
  [STEPS.REVIEW]: 'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.VALIDATION.TITLE',
  [STEPS.CONFIRM]: 'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.TITLE',
  [STEPS.REPORT]: 'CAMPAIGN.WHATSAPP.BULK_DISPATCH.REPORT.TITLE',
};
const stepTitleKey = computed(() => STEP_TITLE_KEYS[step.value]);

const handleFileClick = () => fileInput.value?.click();

const handleFileChange = () => {
  selectedFile.value = fileInput.value?.files[0] || null;
};

const resetState = () => {
  Object.assign(form, { title: '', inboxId: null, templateId: null });
  selectedFile.value = null;
  dispatchId.value = null;
  headers.value = [];
  Object.keys(columnMapping).forEach(key => delete columnMapping[key]);
  validation.value = null;
  sendMode.value = 'now';
  scheduledAt.value = null;
  showSendModeMenu.value = false;
  step.value = STEPS.TEMPLATE;
};

// Bound to Dialog's own @close (fires on Esc, click-outside, or our requestClose()
// below — Dialog's close() emits this itself). Must NOT call dialogRef.close() here:
// that's what emits this event in the first place, so doing it again from inside the
// handler is an infinite loop (confirmed the hard way — Maximum call stack exceeded).
//
// Deliberately does NOT reset state in most cases: an accidental outside-click/Esc while
// filling out the wizard shouldn't throw away the title/file/mapping typed so far. Only once
// the dispatch is actually sent/scheduled (STEPS.REPORT) is there no more in-progress data to
// protect, so any close at that point resets — otherwise reopening would show a stale finished
// report instead of a fresh wizard. Deliberate cancels go through requestClose below instead.
const handleClose = () => {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
  if (step.value === STEPS.REPORT) resetState();
  emit('close');
};

// Bound to our own Cancel/Close footer buttons, which bypass Dialog's built-in ones entirely
// (show-cancel-button/show-confirm-button are both off). A deliberate exit — resets first so
// the next open starts fresh, then asks Dialog to close (handleClose above fires too, but by
// then step is already back to STEPS.TEMPLATE, so its own reset check no-ops).
const requestClose = () => {
  resetState();
  dialogRef.value?.close();
};

const handleUpload = async () => {
  if (!selectedFile.value) return;

  isSubmitting.value = true;
  try {
    const { data } = await whatsappBulkDispatchAPI.create({
      title: form.title,
      inboxId: form.inboxId,
      templateName: selectedTemplate.value.name,
      templateLanguage: selectedTemplate.value.language,
      variableNames: templateVariableNames.value,
      file: selectedFile.value,
    });

    dispatchId.value = data.id;
    headers.value = data.headers;
    Object.assign(columnMapping, data.suggested_mapping);
    if (data.suggested_phone_column) {
      columnMapping[PHONE_KEY] = data.suggested_phone_column;
    }

    step.value = STEPS.MAPPING;
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.API.ERROR_MESSAGE'));
  } finally {
    isSubmitting.value = false;
  }
};

const handleConfirmMapping = async () => {
  isSubmitting.value = true;
  try {
    const { data } = await whatsappBulkDispatchAPI.updateMapping(
      dispatchId.value,
      { ...columnMapping }
    );
    validation.value = {
      validCount: data.valid_count,
      rejectedRows: data.rejected_rows,
      preview: data.preview,
      whatsappCheck: data.whatsapp_check,
    };
    step.value = STEPS.REVIEW;
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.API.ERROR_MESSAGE'));
  } finally {
    isSubmitting.value = false;
  }
};

const pollReport = async () => {
  const { data } = await whatsappBulkDispatchAPI.show(dispatchId.value);
  reportState.status = data.status;
  reportState.totalRecipients = data.total_recipients;
  reportState.sentCount = data.sent_count;
  reportState.failedCount = data.failed_count;
  reportState.failedRowsUrl = data.failed_rows_url;

  if (data.status === 'completed' || data.status === 'failed') {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

const handleSend = async () => {
  isSubmitting.value = true;
  try {
    const scheduledAtIso =
      sendMode.value === 'scheduled' && scheduledAt.value
        ? new Date(scheduledAt.value).toISOString()
        : null;

    const { data } = await whatsappBulkDispatchAPI.confirm(
      dispatchId.value,
      scheduledAtIso
    );
    step.value = STEPS.REPORT;
    reportState.status = data.status;

    if (data.status === 'scheduled') {
      reportState.scheduledAt = data.scheduled_at;
    } else {
      await pollReport();
      pollTimer = setInterval(pollReport, 3000);
    }
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.API.ERROR_MESSAGE'));
  } finally {
    isSubmitting.value = false;
  }
};

const goBack = () => {
  if (step.value > STEPS.TEMPLATE) step.value -= 1;
};

const formattedScheduledAt = computed(() =>
  reportState.scheduledAt
    ? messageStamp(new Date(reportState.scheduledAt * 1000), 'LLL d, h:mm a')
    : ''
);

onBeforeUnmount(() => {
  if (pollTimer) clearInterval(pollTimer);
});

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="lg"
    :title="t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <div class="flex flex-col gap-4">
      <h4 v-if="stepTitleKey" class="mb-0 text-heading-3 text-n-slate-12">
        {{ t(stepTitleKey) }}
      </h4>

      <!-- Step 1: template + basic info -->
      <template v-if="step === STEPS.TEMPLATE">
        <Input
          v-model="form.title"
          :label="
            t(
              'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.TEMPLATE.DISPATCH_TITLE_LABEL'
            )
          "
          :placeholder="
            t(
              'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.TEMPLATE.DISPATCH_TITLE_PLACEHOLDER'
            )
          "
        />
        <div class="flex flex-col gap-1">
          <label class="mb-0.5 text-sm font-medium text-n-slate-12">
            {{
              t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.TEMPLATE.INBOX_LABEL')
            }}
          </label>
          <ComboBox
            v-model="form.inboxId"
            :options="inboxOptions"
            :placeholder="
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.TEMPLATE.INBOX_PLACEHOLDER'
              )
            "
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="mb-0.5 text-sm font-medium text-n-slate-12">
            {{
              t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.TEMPLATE.TEMPLATE_LABEL')
            }}
          </label>
          <ComboBox
            v-model="form.templateId"
            :options="templateOptions"
            :placeholder="
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.TEMPLATE.TEMPLATE_PLACEHOLDER'
              )
            "
          />
        </div>
      </template>

      <!-- Step 2: upload -->
      <template v-else-if="step === STEPS.UPLOAD">
        <p class="text-sm text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.UPLOAD.DESCRIPTION') }}
        </p>
        <div class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-2">
          <p class="text-sm text-n-slate-11">
            {{
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.UPLOAD.TEMPLATE_PREVIEW_LABEL'
              )
            }}
          </p>
          <p class="text-sm whitespace-pre-wrap text-n-slate-12">
            {{ templateBodyText }}
          </p>
          <Button
            :label="
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.UPLOAD.DOWNLOAD_TEMPLATE'
              )
            "
            icon="i-lucide-download"
            color="slate"
            variant="ghost"
            size="sm"
            type="button"
            class="!w-fit"
            @click="downloadTemplateSpreadsheet"
          />
        </div>
        <div class="flex items-center gap-2">
          <span v-if="selectedFile" class="text-sm text-n-slate-12">
            {{ selectedFile.name }}
          </span>
          <Button
            :label="
              selectedFile
                ? t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.UPLOAD.CHANGE')
                : t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.UPLOAD.CHOOSE_FILE')
            "
            icon="i-lucide-upload"
            color="slate"
            variant="ghost"
            size="sm"
            type="button"
            class="!w-fit"
            @click="handleFileClick"
          />
        </div>
        <input
          ref="fileInput"
          type="file"
          accept=".csv,.xlsx"
          class="hidden"
          @change="handleFileChange"
        />
      </template>

      <!-- Step 3: column mapping -->
      <template v-else-if="step === STEPS.MAPPING">
        <p class="text-sm text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.MAPPING.DESCRIPTION') }}
        </p>
        <div class="flex flex-col gap-1">
          <label class="mb-0.5 text-sm font-medium text-n-slate-12">
            {{
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.MAPPING.PHONE_COLUMN_LABEL'
              )
            }}
          </label>
          <ComboBox
            v-model="columnMapping[PHONE_KEY]"
            :options="columnOptions"
            :placeholder="
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.MAPPING.COLUMN_PLACEHOLDER'
              )
            "
          />
        </div>
        <div
          v-for="variableName in templateVariableNames"
          :key="variableName"
          class="flex flex-col gap-1"
        >
          <label class="mb-0.5 text-sm font-medium text-n-slate-12">
            {{
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.MAPPING.VARIABLE_LABEL',
                {
                  number: variableName,
                }
              )
            }}
          </label>
          <ComboBox
            v-model="columnMapping[variableName]"
            :options="columnOptions"
            :placeholder="
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.MAPPING.COLUMN_PLACEHOLDER'
              )
            "
          />
        </div>
      </template>

      <!-- Step 4: review + preview -->
      <template v-else-if="step === STEPS.REVIEW && validation">
        <p v-if="!validation.validCount" class="text-sm text-n-ruby-11">
          {{
            t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.VALIDATION.NO_VALID_ROWS')
          }}
        </p>
        <p v-else class="text-sm text-n-slate-12">
          {{
            t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.VALIDATION.VALID_COUNT', {
              count: validation.validCount,
            })
          }}
        </p>
        <!-- So aparece quando o servico de verificacao respondeu algo de verdade — se estiver
        fora do ar/nao configurado, confirmed+notFound = 0 e essa linha some, sem erro nenhum. -->
        <p v-if="whatsappCheckTotal > 0" class="text-sm text-n-slate-11">
          {{
            t(
              'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.VALIDATION.WHATSAPP_CHECK',
              {
                confirmed: validation.whatsappCheck.confirmed,
                total: whatsappCheckTotal,
              }
            )
          }}
        </p>
        <div v-if="validation.rejectedRows.length" class="flex flex-col gap-1">
          <p class="text-sm text-n-amber-11">
            {{
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.VALIDATION.REJECTED_COUNT',
                { count: validation.rejectedRows.length }
              )
            }}
          </p>
          <ul class="pl-4 text-xs list-disc text-n-slate-11">
            <li v-for="row in validation.rejectedRows" :key="row._row_number">
              {{
                t(
                  'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.VALIDATION.REJECTED_REASON',
                  { row: row._row_number, reason: row._error }
                )
              }}
            </li>
          </ul>
        </div>
        <div v-if="validation.preview.length" class="flex flex-col gap-2">
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.PREVIEW.DESCRIPTION') }}
          </p>
          <div
            v-for="item in validation.preview"
            :key="item.phone_number"
            class="p-3 text-sm rounded-lg bg-n-solid-2 text-n-slate-12"
          >
            <p class="mb-1 text-xs text-n-slate-11">{{ item.phone_number }}</p>
            <p
              v-for="(value, key) in item.template_params.processed_params.body"
              :key="key"
              class="mb-0"
            >
              {{ value }}
            </p>
          </div>
        </div>
      </template>

      <!-- Step 5: confirm -->
      <template v-else-if="step === STEPS.CONFIRM && validation">
        <p class="text-sm text-n-slate-12">
          {{
            t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.DESCRIPTION', {
              count: validation.validCount,
            })
          }}
        </p>
        <div v-if="sendMode === 'scheduled'" class="flex flex-col gap-1">
          <label class="mb-0.5 text-sm font-medium text-n-slate-12">
            {{
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.SCHEDULED_AT_LABEL'
              )
            }}
          </label>
          <Input
            v-model="scheduledAt"
            type="datetime-local"
            :min="currentDateTime"
            :placeholder="
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.SCHEDULED_AT_PLACEHOLDER'
              )
            "
          />
          <p class="mt-1 text-xs text-n-slate-11">
            {{
              t(
                'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.SCHEDULED_AT_HELP_TEXT',
                { interval: scheduledCampaignInterval }
              )
            }}
          </p>
        </div>
      </template>

      <!-- Step 6: report -->
      <template v-else-if="step === STEPS.REPORT">
        <div
          v-if="reportState.status === 'scheduled'"
          class="flex flex-col gap-2"
        >
          <p class="text-sm text-n-slate-12">
            {{
              t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.REPORT.SCHEDULED', {
                date: formattedScheduledAt,
              })
            }}
          </p>
        </div>
        <div
          v-else-if="reportState.status === 'processing'"
          class="flex items-center gap-2"
        >
          <Spinner />
          <p class="mb-0 text-sm text-n-slate-12">
            {{
              t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.REPORT.PROCESSING', {
                sent: reportState.sentCount,
                failed: reportState.failedCount,
                total: reportState.totalRecipients,
              })
            }}
          </p>
        </div>
        <div
          v-else-if="reportState.status === 'completed'"
          class="flex flex-col gap-2"
        >
          <p class="text-sm text-n-slate-12">
            {{
              t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.REPORT.COMPLETED', {
                sent: reportState.sentCount,
                failed: reportState.failedCount,
              })
            }}
          </p>
          <a
            v-if="reportState.failedRowsUrl"
            :href="reportState.failedRowsUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="text-sm text-n-blue-11"
          >
            {{ t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.REPORT.DOWNLOAD_REJECTED') }}
          </a>
        </div>
      </template>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          v-if="step > STEPS.TEMPLATE && step < STEPS.REPORT"
          variant="faded"
          color="slate"
          type="button"
          class="w-full"
          :label="t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.NAVIGATION.BACK')"
          @click="goBack"
        />
        <Button
          v-else-if="step < STEPS.REPORT"
          variant="faded"
          color="slate"
          type="button"
          class="w-full"
          :label="t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.NAVIGATION.CANCEL')"
          @click="requestClose"
        />

        <Button
          v-if="step === STEPS.TEMPLATE"
          class="w-full"
          type="button"
          :disabled="!isTemplateStepValid"
          :label="t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.NAVIGATION.NEXT')"
          @click="step = STEPS.UPLOAD"
        />
        <Button
          v-else-if="step === STEPS.UPLOAD"
          class="w-full"
          type="button"
          :is-loading="isSubmitting"
          :disabled="!selectedFile || isSubmitting"
          :label="t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.NAVIGATION.NEXT')"
          @click="handleUpload"
        />
        <Button
          v-else-if="step === STEPS.MAPPING"
          class="w-full"
          type="button"
          :is-loading="isSubmitting"
          :disabled="!isMappingStepValid || isSubmitting"
          :label="t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.NAVIGATION.NEXT')"
          @click="handleConfirmMapping"
        />
        <Button
          v-else-if="step === STEPS.REVIEW"
          class="w-full"
          type="button"
          :disabled="!validation?.validCount"
          :label="t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.NAVIGATION.NEXT')"
          @click="step = STEPS.CONFIRM"
        />
        <ButtonGroup
          v-else-if="step === STEPS.CONFIRM"
          class="flex items-center w-full"
        >
          <Button
            class="w-full ltr:rounded-r-none rtl:rounded-l-none"
            type="button"
            no-animation
            :is-loading="isSubmitting"
            :disabled="
              isSubmitting || (sendMode === 'scheduled' && !scheduledAt)
            "
            :label="
              sendMode === 'scheduled'
                ? t(
                    'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.SCHEDULE_BUTTON',
                    { count: validation.validCount }
                  )
                : t(
                    'CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.SEND_BUTTON',
                    { count: validation.validCount }
                  )
            "
            @click="handleSend"
          />
          <div
            v-on-click-outside="() => (showSendModeMenu = false)"
            class="relative flex-shrink-0"
          >
            <Button
              icon="i-lucide-chevron-down"
              type="button"
              no-animation
              class="ltr:rounded-l-none rtl:rounded-r-none"
              :disabled="isSubmitting"
              @click.stop="showSendModeMenu = !showSendModeMenu"
            />
            <DropdownMenu
              v-if="showSendModeMenu"
              :menu-items="sendModeMenuItems"
              class="mt-2 ltr:right-0 rtl:left-0 bottom-full"
              @action="handleSendModeAction"
            />
          </div>
        </ButtonGroup>
        <Button
          v-else-if="step === STEPS.REPORT"
          class="w-full"
          type="button"
          :label="t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.NAVIGATION.CLOSE')"
          @click="requestClose"
        />
      </div>
    </template>
  </Dialog>
</template>
