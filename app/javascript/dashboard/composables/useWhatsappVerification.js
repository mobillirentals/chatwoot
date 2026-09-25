import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';

// Um número tem WhatsApp hoje e pode não ter amanhã. O selo gravado no contato é só o último
// resultado conhecido: passado este prazo, quem abrir a tela refaz a checagem ao vivo em vez de
// mostrar o que está no banco. Prazo curto demais vira consulta ao WhatsApp a cada clique, e
// consulta em volume pelo número pareado é justamente o que derruba a sessão do verificador.
export const HORAS_ATE_REVERIFICAR = 12;

// Última checagem ao vivo feita nesta aba, por contato. Evita que abrir a mesma conversa duas
// vezes seguidas gere duas consultas — o selo do banco só é atualizado no contato que foi lido.
const checagensDaSessao = new Map();

const leSelo = contato => {
  const atributos =
    contato?.customAttributes || contato?.custom_attributes || {};
  return atributos.whatsapp_verification || null;
};

const leTelefone = contato =>
  contato?.phoneNumber || contato?.phone_number || '';

const estaVelho = selo => {
  if (!selo) return true;
  const quando = new Date(selo.checked_at ?? selo.checkedAt).getTime();
  if (Number.isNaN(quando)) return true;
  return Date.now() - quando > HORAS_ATE_REVERIFICAR * 60 * 60 * 1000;
};

/**
 * Selo de "esse número tem WhatsApp?" de um contato, com revalidação ao vivo.
 *
 * @param {import('vue').Ref} contato contato reativo (props ou getter do store)
 * @param {{automatico?: boolean}} opcoes automatico = revalida sozinho ao abrir/trocar de contato
 */
export function useWhatsappVerification(contato, { automatico = true } = {}) {
  const store = useStore();
  const { t } = useI18n();

  const checagemLocal = ref(null);
  const verificando = ref(false);

  const selo = computed(
    () =>
      checagemLocal.value ||
      checagensDaSessao.get(contato.value?.id) ||
      leSelo(contato.value)
  );

  const temTelefone = computed(() => Boolean(leTelefone(contato.value)));

  // epoch em segundos, que e o formato aceito por dynamicTime()/timeHelper
  const verificadoEm = computed(() => {
    const quando = selo.value?.checked_at ?? selo.value?.checkedAt;
    const ms = quando ? new Date(quando).getTime() : NaN;
    return Number.isNaN(ms) ? null : Math.floor(ms / 1000);
  });

  const integracaoAtiva = async () => {
    if (!store.getters['integrations/getAppIntegrations']?.length) {
      await store.dispatch('integrations/get');
    }
    const integracao = store.getters['integrations/getIntegration'](
      'whatsapp_number_checker'
    );
    return Boolean(integracao?.enabled);
  };

  // Checagem ao vivo, sempre: o endpoint consulta o serviço na hora e regrava o contato.
  const verificar = async ({ avisarErro = false } = {}) => {
    const id = contato.value?.id;
    if (!id || verificando.value) return;

    verificando.value = true;
    try {
      const { data } = await ContactAPI.verificarWhatsapp(id);
      checagemLocal.value = data.whatsapp_verification;
      checagensDaSessao.set(id, data.whatsapp_verification);
    } catch (error) {
      // 503 = serviço não pareado ou fora do ar. Quem pediu a reverificação merece o aviso;
      // a revalidação automática é silenciosa, ninguém pediu nada.
      if (avisarErro) {
        useAlert(t('CONTACTS_LAYOUT.DETAILS.WHATSAPP_CHECK_FAILED'));
      }
    } finally {
      verificando.value = false;
    }
  };

  const revalidarSeVelho = async () => {
    if (!temTelefone.value || verificando.value) return;
    if (!estaVelho(selo.value)) return;
    if (!(await integracaoAtiva())) return;

    await verificar();
  };

  if (automatico) {
    watch(
      () => contato.value?.id,
      () => {
        checagemLocal.value = null;
        revalidarSeVelho();
      },
      { immediate: true }
    );
  }

  return {
    selo,
    verificando,
    verificadoEm,
    temTelefone,
    verificar,
    revalidarSeVelho,
  };
}
