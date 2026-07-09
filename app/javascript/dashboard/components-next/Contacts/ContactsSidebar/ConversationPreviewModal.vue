<script setup>
import { ref, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import contactAPI from 'dashboard/api/contacts';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  contactId: {
    type: [String, Number],
    required: true,
  },
  conversationId: {
    type: [String, Number],
    required: true,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const iframeRef = ref(null);
const isLoading = ref(true);

onMounted(async () => {
  try {
    const { data } = await contactAPI.previewConversation(
      props.contactId,
      props.conversationId
    );
    isLoading.value = false;
    await nextTick();
    // Same rendering mechanism as the export (document.write), so inline
    // styles render reliably regardless of the dashboard CSP.
    const frame = iframeRef.value;
    const doc = frame?.contentDocument || frame?.contentWindow?.document;
    if (doc) {
      doc.open();
      doc.write(data);
      doc.close();
    }
  } catch {
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PREVIEW.ERROR'));
    emit('close');
  }
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
    @click.self="emit('close')"
  >
    <div
      class="flex flex-col w-full max-w-3xl overflow-hidden shadow-2xl bg-n-solid-1 rounded-xl max-h-[85vh]"
    >
      <div
        class="flex items-center justify-between px-5 py-3 border-b border-n-weak shrink-0"
      >
        <h3 class="text-base font-semibold text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PREVIEW.TITLE') }}
        </h3>
        <button
          class="transition-colors text-n-slate-10 hover:text-n-slate-12"
          :aria-label="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PREVIEW.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>
      <div class="flex-1 min-h-0 bg-white">
        <div
          v-if="isLoading"
          class="flex items-center justify-center h-64 bg-n-solid-1"
        >
          <Spinner />
        </div>
        <iframe
          v-else
          ref="iframeRef"
          :title="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PREVIEW.TITLE')"
          class="w-full h-[72vh] border-0"
        />
      </div>
    </div>
  </div>
</template>
