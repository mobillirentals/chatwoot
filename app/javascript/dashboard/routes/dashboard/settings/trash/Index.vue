<script setup>
import { useAlert } from 'dashboard/composables';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import trashAPI from 'dashboard/api/trash';
import ConversationPreviewModal from 'dashboard/components-next/Contacts/ContactsSidebar/ConversationPreviewModal.vue';
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const records = ref([]);
const previewItem = ref(null);
const meta = ref({
  currentPage: 1,
  totalEntries: 0,
  perPage: 15,
});
const uiFlags = ref({
  fetchingList: false,
});

const routerPage = computed(() => Number(route.query.page ?? 1));

const fetchTrashItems = async page => {
  uiFlags.value.fetchingList = true;
  try {
    const response = await trashAPI.get({ page });
    records.value = response.data.conversations;
    meta.value = response.data.meta;
  } catch (error) {
    const errorMessage =
      error?.response?.data?.message || t('TRASH.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  } finally {
    uiFlags.value.fetchingList = false;
  }
};

const handleRestore = async id => {
  try {
    await trashAPI.restore(id);
    useAlert(t('TRASH.RESTORE_SUCCESS_MESSAGE'));
    fetchTrashItems(routerPage.value);
  } catch (error) {
    useAlert(t('TRASH.RESTORE_ERROR_MESSAGE'));
  }
};

const onPageChange = page => {
  router.push({ name: 'trash_list', query: { page: page } });
};

onMounted(() => {
  fetchTrashItems(routerPage.value);
});

watch(routerPage, (newPage, oldPage) => {
  if (newPage !== oldPage) {
    fetchTrashItems(newPage);
  }
});

const tableHeaders = computed(() => {
  return [
    t('TRASH.LIST.TABLE_HEADER.RESOURCE'),
    t('TRASH.LIST.TABLE_HEADER.INBOX'),
    t('TRASH.LIST.TABLE_HEADER.CONTACT'),
    t('TRASH.LIST.TABLE_HEADER.DELETED_AT'),
    t('TRASH.LIST.TABLE_HEADER.ACTIONS'),
  ];
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingList"
    :loading-message="$t('TRASH.LOADING')"
    :no-records-found="!records.length"
    :no-records-message="$t('TRASH.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('TRASH.HEADER')"
        :description="$t('TRASH.DESCRIPTION')"
        :link-text="$t('TRASH.LEARN_MORE')"
        feature-name="trash"
      />
    </template>
    <template #body>
      <div class="flex flex-col">
        <BaseTable :headers="tableHeaders" :items="records">
          <template #row="{ items }">
            <BaseTableRow v-for="item in items" :key="item.id" :item="item">
              <template #default>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-12 font-medium">
                    #{{ item.display_id }}
                  </span>
                </BaseTableCell>

                <BaseTableCell>
                  <span class="text-body-main text-n-slate-11">
                    {{ item.inbox ? item.inbox.name : '—' }}
                  </span>
                </BaseTableCell>

                <BaseTableCell>
                  <span class="text-body-main text-n-slate-12">
                    {{ item.contact ? item.contact.name : '—' }}
                  </span>
                </BaseTableCell>

                <BaseTableCell>
                  <span
                    class="text-body-main text-n-slate-11 whitespace-nowrap"
                  >
                    {{
                      messageTimestamp(item.deleted_at, 'MMM dd, yyyy hh:mm a')
                    }}
                  </span>
                </BaseTableCell>

                <BaseTableCell class="w-24">
                  <div class="flex items-center gap-2">
                    <button
                      class="flex items-center justify-center p-1.5 rounded-lg hover:bg-n-alpha-1 text-n-slate-11 hover:text-n-brand transition-colors"
                      :title="$t('TRASH.ACTION_TOOLTIP.VIEW')"
                      @click="previewItem = item"
                    >
                      <span class="i-lucide-eye size-4" />
                    </button>
                    <button
                      class="flex items-center justify-center p-1.5 rounded-lg hover:bg-n-alpha-1 text-n-slate-11 hover:text-n-brand transition-colors"
                      :title="$t('TRASH.ACTION_TOOLTIP.RESTORE')"
                      @click="handleRestore(item.id)"
                    >
                      <span class="i-lucide-rotate-ccw size-4" />
                    </button>
                  </div>
                </BaseTableCell>
              </template>
            </BaseTableRow>
          </template>
        </BaseTable>
        <PaginationFooter
          :current-page="Number(meta.currentPage)"
          :total-items="meta.totalEntries"
          :items-per-page="meta.perPage"
          class="!px-0"
          @update:current-page="onPageChange"
        />
      </div>
      <ConversationPreviewModal
        v-if="previewItem"
        :conversation-id="previewItem.display_id"
        :fetch-messages="() => trashAPI.messages(previewItem.id)"
        @close="previewItem = null"
      />
    </template>
  </SettingsLayout>
</template>
