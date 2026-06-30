<script>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import FormInput from '../../../components/Form/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { DEFAULT_REDIRECT_URL } from 'dashboard/constants/globals';
import { setNewPassword } from '../../../api/auth';

export default {
  components: {
    FormInput,
    NextButton,
  },
  props: {
    resetPasswordToken: { type: String, default: '' },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      credentials: {
        confirmPassword: '',
        password: '',
      },
      newPasswordAPI: {
        message: '',
        showLoading: false,
      },
      error: '',
      ssoActivating: false,
    };
  },
  computed: {
    isSsoOnlyMode() {
      return window.chatwootConfig.emailLoginEnabled === 'false';
    },
  },
  mounted() {
    if (!this.resetPasswordToken) {
      window.location = DEFAULT_REDIRECT_URL;
      return;
    }
    if (this.isSsoOnlyMode) {
      this.activateViaSso();
    }
  },
  validations: {
    credentials: {
      password: {
        required,
        minLength: minLength(6),
      },
      confirmPassword: {
        required,
        minLength: minLength(6),
        isEqPassword(value) {
          if (value !== this.credentials.password) {
            return false;
          }
          return true;
        },
      },
    },
  },
  methods: {
    showAlertMessage(message) {
      this.newPasswordAPI.showLoading = false;
      useAlert(message);
    },
    async activateViaSso() {
      this.ssoActivating = true;
      const randomPassword = `Sso!${Math.random().toString(36).slice(2, 14)}${Math.random().toString(36).slice(2, 6)}`;
      try {
        await setNewPassword({
          resetPasswordToken: this.resetPasswordToken,
          password: randomPassword,
          confirmPassword: randomPassword,
        });
        window.location = `${DEFAULT_REDIRECT_URL}?sso_activated=1`;
      } catch {
        this.ssoActivating = false;
        useAlert(this.$t('SET_NEW_PASSWORD.API.ERROR_MESSAGE'));
      }
    },
    submitForm() {
      this.newPasswordAPI.showLoading = true;
      const credentials = {
        confirmPassword: this.credentials.confirmPassword,
        password: this.credentials.password,
        resetPasswordToken: this.resetPasswordToken,
      };
      setNewPassword(credentials)
        .then(() => {
          window.location = DEFAULT_REDIRECT_URL;
        })
        .catch(error => {
          this.showAlertMessage(
            error?.message || this.$t('SET_NEW_PASSWORD.API.ERROR_MESSAGE')
          );
        });
    },
  },
};
</script>

<template>
  <div
    class="flex flex-col justify-center w-full min-h-screen py-12 bg-n-brand/5 dark:bg-n-background sm:px-6 lg:px-8"
  >
    <!-- SSO-only mode: auto-activate, no password form -->
    <div
      v-if="isSsoOnlyMode"
      class="bg-white shadow sm:mx-auto sm:w-full sm:max-w-lg dark:bg-n-solid-2 p-11 sm:shadow-lg sm:rounded-lg text-center"
    >
      <h1 class="mb-3 text-2xl font-medium text-n-slate-12">
        {{ $t('SET_NEW_PASSWORD.SSO_ACTIVATING.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ $t('SET_NEW_PASSWORD.SSO_ACTIVATING.DESCRIPTION') }}
      </p>
    </div>

    <!-- Normal mode: password form -->
    <form
      v-else
      class="bg-white shadow sm:mx-auto sm:w-full sm:max-w-lg dark:bg-n-solid-2 p-11 sm:shadow-lg sm:rounded-lg"
      @submit.prevent="submitForm"
    >
      <h1
        class="mb-1 text-2xl font-medium tracking-tight text-left text-n-slate-12"
      >
        {{ $t('SET_NEW_PASSWORD.TITLE') }}
      </h1>

      <div class="space-y-5">
        <FormInput
          v-model="credentials.password"
          class="mt-3"
          name="password"
          type="password"
          :has-error="v$.credentials.password.$error"
          :error-message="$t('SET_NEW_PASSWORD.PASSWORD.ERROR')"
          :placeholder="$t('SET_NEW_PASSWORD.PASSWORD.PLACEHOLDER')"
          @blur="v$.credentials.password.$touch"
        />
        <FormInput
          v-model="credentials.confirmPassword"
          class="mt-3"
          name="confirm_password"
          type="password"
          :has-error="v$.credentials.confirmPassword.$error"
          :error-message="$t('SET_NEW_PASSWORD.CONFIRM_PASSWORD.ERROR')"
          :placeholder="$t('SET_NEW_PASSWORD.CONFIRM_PASSWORD.PLACEHOLDER')"
          @blur="v$.credentials.confirmPassword.$touch"
        />
        <NextButton
          lg
          type="submit"
          data-testid="submit_button"
          class="w-full"
          :label="$t('SET_NEW_PASSWORD.SUBMIT')"
          :disabled="
            v$.credentials.password.$invalid ||
            v$.credentials.confirmPassword.$invalid ||
            newPasswordAPI.showLoading
          "
          :is-loading="newPasswordAPI.showLoading"
        />
      </div>
    </form>
  </div>
</template>
