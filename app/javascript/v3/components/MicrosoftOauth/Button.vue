<script>
export default {
  computed: {
    csrfToken() {
      return document
        .querySelector('meta[name="csrf-token"]')
        ?.getAttribute('content');
    },
  },
  methods: {
    submitMicrosoftLogin() {
      this.$refs.microsoftForm.submit();
    },
  },
};
</script>

<template>
  <div class="flex flex-col">
    <form
      ref="microsoftForm"
      method="post"
      action="/auth/entra_id"
      class="hidden"
    >
      <input type="hidden" name="authenticity_token" :value="csrfToken" />
    </form>
    <button
      type="button"
      class="inline-flex justify-center w-full px-4 py-3 bg-n-background dark:bg-n-solid-3 items-center rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2 cursor-pointer"
      @click="submitMicrosoftLogin"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 23 23"
        class="h-5 w-5 flex-shrink-0"
      >
        <path fill="#f3f3f3" d="M0 0h23v23H0z" />
        <path fill="#f35325" d="M1 1h10v10H1z" />
        <path fill="#81bc06" d="M12 1h10v10H12z" />
        <path fill="#05a6f0" d="M1 12h10v10H1z" />
        <path fill="#ffba08" d="M12 12h10v10H12z" />
      </svg>
      <span class="ml-2 text-base font-medium text-n-slate-12">
        {{ $t('LOGIN.AZURE.LABEL') }}
      </span>
    </button>
  </div>
</template>
