<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';
import AnalyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { SESSION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';

// components
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import FormInput from '../../components/Form/Input.vue';
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import MicrosoftOAuthButton from '../../components/MicrosoftOauth/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';
import SessionLimitOverlay from 'dashboard/components/auth/SessionLimitOverlay.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';
const USER_NOT_CONFIRMED_ERROR_CODE = 'user_not_confirmed';
const AUTH_ERROR_TOAST_DURATION = 6000;

export default {
  components: {
    FormInput,
    GoogleOAuthButton,
    MicrosoftOAuthButton,
    Spinner,
    NextButton,
    SimpleDivider,
    MfaVerification,
    SessionLimitOverlay,
    Icon,
  },
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      // Os dois vivem em public/ e são servidos pelo Rails, não pelo build do front. Por isso
      // entram como valor, não como atributo fixo: atributo fixo o Vite tenta resolver como
      // import e o módulo quebra.
      fotoLogin: '/brand/login-foto.jpg',
      fotoLoginMobile: '/brand/login-foto-mobile.jpg',
      marcaMobilli: '/brand/mobilli.svg',
      // nome próprio não se traduz, então a assinatura vive aqui em vez de virar chave de i18n
      assinatura: {
        empresa: 'by Mobílli Rentals',
        autor: 'Egnner Bruno',
        github: 'https://github.com/egnnerbruno',
      },
      // We need to initialize the component with any
      // properties that will be used in it
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
      sessionsLimitReached: false,
      limitedSessions: [],
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    allowedLoginMethods() {
      return window.chatwootConfig.allowedLoginMethods || ['email'];
    },
    showGoogleOAuth() {
      return (
        this.allowedLoginMethods.includes('google_oauth') &&
        Boolean(window.chatwootConfig.googleOAuthClientId)
      );
    },
    showMicrosoftOAuth() {
      return (
        this.allowedLoginMethods.includes('entra_id') &&
        Boolean(window.chatwootConfig.azureClientId)
      );
    },
    showEmailLogin() {
      return window.chatwootConfig.emailLoginEnabled !== 'false';
    },
    // O logo vem da configuração da instalação; quando ela está vazia (instalação nova, banco
    // local recém-criado), cai pros arquivos de marca que já vivem em public/brand-assets —
    // tela de entrada sem logo é pior do que tela com o logo padrão da casa.
    logoClaro() {
      return this.globalConfig.logo || '/brand-assets/logo.svg';
    },
    logoEscuro() {
      return this.globalConfig.logoDark || '/brand-assets/logo_dark.svg';
    },
    showSignupLink() {
      return window.chatwootConfig.signupEnabled === 'true';
    },
    showSamlLogin() {
      return this.allowedLoginMethods.includes('saml');
    },
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
    if (this.$route?.query?.sso_activated) {
      useAlert(this.$t('LOGIN.SSO.ACCOUNT_ACTIVATED'));
      this.$router.replace({
        query: { ...this.$route.query, sso_activated: undefined },
      });
    }
  },
  mounted() {
    if (this.authError) {
      // Wait for the sibling snackbar to mount and subscribe to toast events.
      this.$nextTick(() => {
        const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
        // Use a method to get the translated text to avoid dynamic key warning
        const translatedMessage = this.getTranslatedMessage(messageKey);
        useAlert(translatedMessage, { duration: AUTH_ERROR_TOAST_DURATION });
        // wait for idle state
        this.requestIdleCallbackPolyfill(() => {
          // Remove the error query param from the url
          const { query } = this.$route;
          this.$router.replace({ query: { ...query, error: undefined } });
        });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      // Avoid dynamic key warning by handling each case explicitly
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    // TODO: Remove this when Safari gets wider support
    // Ref: https://caniuse.com/requestidlecallback
    //
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        // Fallback for safari
        // Using a delay of 0 allows the callback to be executed asynchronously
        // in the next available event loop iteration, similar to requestIdleCallback
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      // Detects impersonation mode via URL and sets a session flag to prevent user settings changes during impersonation.
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
      };

      login(credentials)
        .then(result => {
          // Check if MFA is required
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            return;
          }

          // Check if sessions limit reached
          if (result?.sessionsLimitReached) {
            this.loginApi.showLoading = false;
            this.sessionsLimitReached = true;
            this.limitedSessions = result.sessions;
            AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
            return;
          }

          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          if (response?.errorCode === USER_NOT_CONFIRMED_ERROR_CODE) {
            this.loginApi.showLoading = false;
            this.$router.push({
              name: 'auth_verify_email',
              state: { email: credentials.email },
            });
            return;
          }

          // Reset URL Params if the authentication is invalid
          if (this.email) {
            window.location = '/app/login';
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.submitLogin();
    },
    handleMfaVerified() {
      // MFA verification successful, continue with login
      this.handleImpersonation();
      window.location = '/app';
    },
    handleMfaCancel() {
      // User cancelled MFA, reset state
      this.mfaRequired = false;
      this.mfaToken = null;
      this.credentials.password = '';
    },
    retryLoginWithParams(extraParams) {
      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        ...extraParams,
      };

      this.sessionsLimitReached = false;
      this.limitedSessions = [];
      this.loginApi.showLoading = true;
      login(credentials)
        .then(result => {
          if (result?.sessionsLimitReached) {
            this.loginApi.showLoading = false;
            this.sessionsLimitReached = true;
            this.limitedSessions = result.sessions;
            AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
            return;
          }
          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    handleSessionRevoke(sessionId) {
      this.retryLoginWithParams({ revoke_session_id: sessionId });
    },
    handleSessionRevokeAll() {
      this.retryLoginWithParams({ revoke_all_sessions: true });
    },
    handleSessionLimitCancel() {
      this.sessionsLimitReached = false;
      this.limitedSessions = [];
      this.credentials.password = '';
    },
  },
};
</script>

<template>
  <main class="entrada">
    <!-- a foto é a tela: quem está do outro lado da conversa -->
    <div class="entrada__foto">
      <picture>
        <source media="(max-width: 1023px)" :srcset="fotoLoginMobile" />
        <img :src="fotoLogin" alt="" />
      </picture>
    </div>
    <div class="entrada__sombra" aria-hidden="true" />

    <!-- o bloco de entrar flutua por cima dela -->
    <div class="entrada__painel">
      <div
        class="entrada__cartao"
        :class="{ 'animate-wiggle': loginApi.hasErrored }"
      >
        <img
          :src="logoClaro"
          :alt="globalConfig.installationName"
          class="block w-auto h-8 dark:hidden"
        />
        <img
          :src="logoEscuro"
          :alt="globalConfig.installationName"
          class="hidden w-auto h-8 dark:block"
        />
        <h2 class="mt-8 text-2xl font-medium text-n-slate-12">
          {{ replaceInstallationName($t('LOGIN.TITLE')) }}
        </h2>
        <p v-if="showSignupLink" class="mt-2 text-sm text-n-slate-11">
          {{ $t('COMMON.OR') }}
          <router-link
            to="auth/signup"
            class="lowercase text-link text-n-brand"
          >
            {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
          </router-link>
        </p>

        <!-- Session Limit Section -->
        <section v-if="sessionsLimitReached" class="mt-8">
          <SessionLimitOverlay
            :sessions="limitedSessions"
            @revoke="handleSessionRevoke"
            @revoke-all="handleSessionRevokeAll"
            @cancel="handleSessionLimitCancel"
          />
        </section>

        <!-- MFA Verification Section -->
        <section v-else-if="mfaRequired" class="mt-8">
          <MfaVerification
            :mfa-token="mfaToken"
            @verified="handleMfaVerified"
            @cancel="handleMfaCancel"
          />
        </section>

        <!-- Regular Login Section -->
        <section v-else class="mt-8">
          <div v-if="!email">
            <form
              v-if="showEmailLogin"
              class="space-y-5"
              @submit.prevent="submitFormLogin"
            >
              <FormInput
                v-model="credentials.email"
                name="email_address"
                type="text"
                data-testid="email_input"
                :tabindex="1"
                required
                :label="$t('LOGIN.EMAIL.LABEL')"
                :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
                :has-error="v$.credentials.email.$error"
                @input="v$.credentials.email.$touch"
              />
              <FormInput
                v-model="credentials.password"
                type="password"
                name="password"
                data-testid="password_input"
                required
                :tabindex="2"
                :label="$t('LOGIN.PASSWORD.LABEL')"
                :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
                :has-error="v$.credentials.password.$error"
                @input="v$.credentials.password.$touch"
              >
                <p v-if="!globalConfig.disableUserProfileUpdate">
                  <router-link
                    to="auth/reset/password"
                    class="text-sm text-link"
                    tabindex="4"
                  >
                    {{ $t('LOGIN.FORGOT_PASSWORD') }}
                  </router-link>
                </p>
              </FormInput>
              <NextButton
                lg
                type="submit"
                data-testid="submit_button"
                class="w-full"
                :tabindex="3"
                :label="$t('LOGIN.SUBMIT')"
                :disabled="loginApi.showLoading"
                :is-loading="loginApi.showLoading"
              />
            </form>
            <div
              class="flex flex-col gap-4"
              :class="{ 'mt-4': showEmailLogin }"
            >
              <SimpleDivider
                v-if="
                  (showGoogleOAuth || showMicrosoftOAuth || showSamlLogin) &&
                  showEmailLogin
                "
                :label="$t('COMMON.OR')"
                class="uppercase"
              />
              <GoogleOAuthButton v-if="showGoogleOAuth" />
              <MicrosoftOAuthButton v-if="showMicrosoftOAuth" />
              <div v-if="showSamlLogin" class="text-center">
                <router-link
                  to="/app/login/sso"
                  class="inline-flex justify-center w-full px-4 py-3 items-center bg-n-background dark:bg-n-solid-3 rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
                >
                  <Icon
                    icon="i-lucide-lock-keyhole"
                    class="size-5 text-n-slate-11"
                  />
                  <span class="ml-2 text-base font-medium text-n-slate-12">
                    {{ $t('LOGIN.SAML.LABEL') }}
                  </span>
                </router-link>
              </div>
            </div>
          </div>
          <div v-else class="flex items-center justify-center">
            <Spinner color-scheme="primary" size="" />
          </div>
        </section>
        <footer class="entrada__rodape">
          <img :src="marcaMobilli" alt="" class="entrada__marca" />
          {{ assinatura.empresa }}
          <span class="entrada__barra">|</span>
          <a
            :href="assinatura.github"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ assinatura.autor }}
          </a>
        </footer>
      </div>
    </div>
  </main>
</template>

<style scoped>
/* A foto ocupa a tela inteira e o bloco de entrar flutua por cima dela, encostado à esquerda.
   As cores do bloco saem dos tokens do design system (--slate-*), que já trocam sozinhos entre
   o tema claro e o escuro. */
.entrada {
  position: relative;
  display: flex;
  align-items: center;
  width: 100%;
  min-height: 100vh;
  min-height: 100dvh;
  overflow: hidden;
  background: rgb(var(--slate-2));
}

.entrada__foto {
  position: absolute;
  inset: 0;
  z-index: 0;
}

.entrada__foto picture,
.entrada__foto img {
  display: block;
  width: 100%;
  height: 100%;
}

.entrada__foto img {
  object-fit: cover;
  object-position: 62% 45%;
}

/* escurece o lado onde o bloco fica, pra ele assentar na foto em vez de boiar */
.entrada__sombra {
  position: absolute;
  inset: 0;
  z-index: 1;
  background: linear-gradient(
    100deg,
    rgb(0 0 0 / 0.55) 0%,
    rgb(0 0 0 / 0.3) 45%,
    rgb(0 0 0 / 0) 78%
  );
}

.entrada__painel {
  position: relative;
  z-index: 2;
  display: flex;
  justify-content: center;
  width: 100%;
  padding: 2.5rem 1.5rem;
}

.entrada__cartao {
  width: 100%;
  max-width: 25rem;
  padding: 2.5rem;
  background: rgb(var(--slate-1) / 0.97);
  border-radius: 24px;
  box-shadow: 0 30px 60px rgb(0 0 0 / 0.35);
}

.entrada__rodape {
  margin-top: 2rem;
  padding-top: 1.25rem;
  font-size: 12px;
  color: rgb(var(--slate-11));
  text-align: center;
  border-top: 1px solid rgb(var(--slate-4));
}

.entrada__rodape a {
  color: inherit;
  text-decoration: none;
  border-bottom: 1px solid rgb(var(--slate-8) / 0.6);
}

.entrada__rodape a:hover {
  color: rgb(var(--blue-11));
  border-bottom-color: rgb(var(--blue-9) / 0.7);
}

.entrada__barra {
  margin-inline: 6px;
  opacity: 0.5;
}

.entrada__marca {
  display: inline-block;
  height: 15px;
  margin-right: 7px;
  vertical-align: -3px;
}

/* na tela estreita o bloco fica no meio da foto, então o véu escurece por igual em vez de
   puxar pro lado, e o corte segue o retrato: rosto acima do cartão */
@media (max-width: 1023px) {
  .entrada__foto img {
    object-position: 50% 35%;
  }

  .entrada__sombra {
    background: linear-gradient(
      180deg,
      rgb(0 0 0 / 0.3) 0%,
      rgb(0 0 0 / 0.55) 55%,
      rgb(0 0 0 / 0.7) 100%
    );
  }
}

/* na tela larga o bloco sai do meio e encosta à esquerda, como na referência */
@media (min-width: 1024px) {
  .entrada__painel {
    justify-content: flex-start;
    padding: 3rem clamp(3rem, 8vw, 9rem);
  }
}
</style>
