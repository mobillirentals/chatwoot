<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  template: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['deleted']);

const { t } = useI18n();
const dialogRef = ref(null);
const apagando = ref(false);

// O modelo vive na Meta, por conta comercial: apagar precisa da caixa que fala com aquela conta.
const inboxId = computed(
  () =>
    props.template?.inboxes?.find(
      inbox => inbox.provider_config?.business_account_id
    )?.id
);

const apagar = async () => {
  if (!inboxId.value || apagando.value) return;

  apagando.value = true;
  try {
    await InboxesAPI.destroyMessageTemplate(inboxId.value, {
      name: props.template.name,
      templateId: props.template.id,
    });
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.CONFIRM_DELETE.SUCCESS'));
    emit('deleted');
    dialogRef.value?.close();
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('WHATSAPP_TEMPLATE_MGMT.CONFIRM_DELETE.ERROR')
    );
  } finally {
    apagando.value = false;
  }
};

defineExpose({ dialogRef });
</script>

<template>
  <!-- O nome do modelo vai no título porque a lista some atrás do diálogo: sem ele a pessoa
       confirma sem ver qual dos 23 modelos está prestes a apagar. -->
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="
      $t('WHATSAPP_TEMPLATE_MGMT.CONFIRM_DELETE.TITLE', {
        name: template?.name,
      })
    "
    :description="$t('WHATSAPP_TEMPLATE_MGMT.CONFIRM_DELETE.DESCRIPTION')"
    :confirm-button-label="$t('WHATSAPP_TEMPLATE_MGMT.CONFIRM_DELETE.CONFIRM')"
    :is-loading="apagando"
    :disable-confirm-button="!inboxId"
    @confirm="apagar"
  />
</template>
