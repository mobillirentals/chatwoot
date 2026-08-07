<script setup>
import { useI18n } from 'vue-i18n';
import { getI18nKey } from 'dashboard/routes/dashboard/settings/helper/settingsHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import { BaseTableRow, BaseTableCell } from 'dashboard/components-next/table';

defineProps({
  roles: {
    type: Array,
    required: true,
  },
  loading: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['edit', 'delete']);

const { t } = useI18n();
</script>

<template>
  <BaseTableRow
    v-for="customRole in roles"
    :key="customRole.id"
    :item="customRole"
  >
    <template #default>
      <BaseTableCell class="max-w-40">
        <span class="text-body-main text-n-slate-12 truncate block">
          {{ customRole.name }}
        </span>
      </BaseTableCell>

      <BaseTableCell class="max-w-xs">
        <span class="text-body-main text-n-slate-11 line-clamp-2 block">
          {{ customRole.description }}
        </span>
      </BaseTableCell>

      <BaseTableCell class="max-w-sm">
        <div class="flex flex-wrap gap-1.5">
          <Label
            v-for="permission in customRole.permissions"
            :key="permission"
            :label="t(getI18nKey('CUSTOM_ROLE.PERMISSIONS', permission))"
            compact
          />
        </div>
      </BaseTableCell>

      <BaseTableCell align="end" class="w-24">
        <div class="flex gap-3 justify-end flex-shrink-0">
          <Button
            v-tooltip.top="$t('CUSTOM_ROLE.EDIT.BUTTON_TEXT')"
            icon="i-woot-edit-pen"
            slate
            sm
            @click="emit('edit', customRole)"
          />
          <Button
            v-tooltip.top="$t('CUSTOM_ROLE.DELETE.BUTTON_TEXT')"
            icon="i-woot-bin"
            slate
            sm
            class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
            :is-loading="loading[customRole.id]"
            @click="emit('delete', customRole)"
          />
        </div>
      </BaseTableCell>
    </template>
  </BaseTableRow>
</template>
