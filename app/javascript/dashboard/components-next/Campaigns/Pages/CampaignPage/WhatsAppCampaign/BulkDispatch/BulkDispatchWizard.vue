<script setup>
import { reactive, computed, ref, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import whatsappBulkDispatchAPI from 'dashboard/api/whatsappBulkDispatch';

const emit = defineEmits(['close']);
const { t } = useI18n();

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
const reportState = reactive({
  status: 'draft',
  totalRecipients: 0,
  sentCount: 0,
  failedCount: 0,
  failedRowsUrl: null,
});
let pollTimer = null;

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

// Column names match the "telefone" / "variavel_N" hints ColumnMapperService already
// looks for, so uploading the file back auto-suggests the mapping in the next step.
const downloadTemplateSpreadsheet = () => {
  const template = selectedTemplate.value;
  if (!template) return;

  const headerRow = [
    'telefone',
    ...templateVariableNames.value.map(name => `variavel_${name}`),
  ];
  const csvContent = `${headerRow.join(',')}\n`;
  // BOM so Excel (still the default spreadsheet app for most operators here) opens the
  // CSV as UTF-8 instead of guessing a legacy codepage.
  const utf8Bom = '﻿';

  const blob = new Blob([utf8Bom, csvContent], {
    type: 'text/csv;charset=utf-8;',
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `modelo-${template.name}.csv`;
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
  step.value = STEPS.TEMPLATE;
};

// Bound to Dialog's own @close (fires on Esc, click-outside, or our requestClose()
// below — Dialog's close() emits this itself). Must NOT call dialogRef.close() here:
// that's what emits this event in the first place, so doing it again from inside the
// handler is an infinite loop (confirmed the hard way — Maximum call stack exceeded).
const handleClose = () => {
  if (pollTimer) clearInterval(pollTimer);
  resetState();
  emit('close');
};

// Bound to our own Cancel/Close footer buttons, which bypass Dialog's built-in ones
// entirely (show-cancel-button/show-confirm-button are both off). Only asks Dialog to
// close; handleClose above does the state cleanup once Dialog's own @close fires back.
const requestClose = () => {
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
    await whatsappBulkDispatchAPI.confirm(dispatchId.value);
    step.value = STEPS.REPORT;
    await pollReport();
    pollTimer = setInterval(pollReport, 3000);
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.API.ERROR_MESSAGE'));
  } finally {
    isSubmitting.value = false;
  }
};

const goBack = () => {
  if (step.value > STEPS.TEMPLATE) step.value -= 1;
};

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
            t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.SEND_BUTTON', {
              count: validation.validCount,
            })
          }}
        </p>
      </template>

      <!-- Step 6: report -->
      <template v-else-if="step === STEPS.REPORT">
        <div
          v-if="reportState.status === 'processing'"
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
        <Button
          v-else-if="step === STEPS.CONFIRM"
          class="w-full"
          type="button"
          :is-loading="isSubmitting"
          :disabled="isSubmitting"
          :label="
            t('CAMPAIGN.WHATSAPP.BULK_DISPATCH.STEPS.CONFIRM.SEND_BUTTON', {
              count: validation.validCount,
            })
          "
          @click="handleSend"
        />
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
