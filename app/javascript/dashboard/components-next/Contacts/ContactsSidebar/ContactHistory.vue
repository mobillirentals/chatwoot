<script setup>
import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationCard from 'dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue';
import ConversationExportModal from 'dashboard/components-next/Contacts/ContactsSidebar/ConversationExportModal.vue';

const { t } = useI18n();
const route = useRoute();

const conversations = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);
const contactsById = useMapGetter('contacts/getContactById');
const stateInbox = useMapGetter('inboxes/getInboxById');
const accountLabels = useMapGetter('labels/getLabels');
const currentUser = useMapGetter('auth/getCurrentUser');

const accountLabelsValue = computed(() => accountLabels.value);

const uiFlags = useMapGetter('contactConversations/getUIFlags');
const isFetching = computed(() => uiFlags.value.isFetching);

const contactId = computed(() => route.params.contactId);

const contactConversations = computed(() =>
  conversations.value(contactId.value)
);

const canExport = computed(() => {
  const role = currentUser.value?.role;
  return role === 'administrator' || role === 'supervisor';
});

const showExportModal = ref(false);
</script>

<template>
  <div
    v-if="isFetching"
    class="flex items-center justify-center py-10 text-n-slate-11"
  >
    <Spinner />
  </div>
  <template v-else>
    <!-- Export button — visible only to admin/supervisor -->
    <div
      v-if="canExport && contactConversations.length > 0"
      class="flex justify-end px-6 py-2 border-b border-n-weak"
    >
      <button
        class="flex items-center gap-1.5 text-xs font-medium text-n-slate-11 hover:text-woot-500 transition-colors"
        @click="showExportModal = true"
      >
        <span class="i-lucide-file-down size-3.5" />
        {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT.TRIGGER_BUTTON') }}
      </button>
    </div>

    <div
      v-if="contactConversations.length > 0"
      class="px-6 divide-y divide-n-strong [&>*:hover]:!border-y-transparent [&>*:hover+*]:!border-t-transparent"
    >
      <ConversationCard
        v-for="conversation in contactConversations"
        :key="conversation.id"
        :conversation="conversation"
        :contact="contactsById(conversation.meta.sender.id)"
        :state-inbox="stateInbox(conversation.inboxId)"
        :account-labels="accountLabelsValue"
        class="rounded-none hover:rounded-xl hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3"
      />
    </div>
    <p v-else class="px-6 py-10 text-sm leading-6 text-center text-n-slate-11">
      {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EMPTY_STATE') }}
    </p>

    <!-- Export modal -->
    <ConversationExportModal
      v-if="showExportModal"
      :contact-id="contactId"
      :conversations="contactConversations"
      @close="showExportModal = false"
    />
  </template>
</template>
