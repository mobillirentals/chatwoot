import { computed, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  aplicaTemaPersonalizado,
  aplicaFundoDoChat,
  aplicaClaridadeDoFundo,
  vigiaTrocaDeTema,
  CLARIDADE_PADRAO,
} from 'dashboard/helper/aparencia';

/**
 * Tema próprio e fundo da conversa, guardados no perfil de quem está usando.
 *
 * Fica nas `ui_settings` (e não no localStorage, onde vive o claro/escuro) de propósito: assim a
 * escolha acompanha a pessoa em qualquer computador, que é o que se espera de uma preferência
 * visual do perfil.
 *
 * Aplicar e salvar são coisas separadas aqui: a tela de Aparência mostra a mudança na hora
 * (`aplicarVisual`) enquanto a pessoa experimenta, e só grava quando ela confirma
 * (`salvarPreferencias`) — uma ida à API por escolha testada seria desperdício, e deixaria salvo
 * o que a pessoa só estava olhando.
 */
export function useAparencia() {
  const { uiSettings } = useUISettings();
  const store = useStore();

  const temaPersonalizadoSalvo = computed(
    () => uiSettings.value?.custom_theme || ''
  );
  const fundoDaConversaSalvo = computed(
    () => uiSettings.value?.chat_background || ''
  );
  // inventário do que a pessoa enviou: é estado do servidor (arquivos que existem), não
  // preferência visual, então é salvo na hora do envio e não espera o botão Salvar
  const envios = computed(
    () => uiSettings.value?.chat_background_uploads || []
  );

  const registrarEnvios = lista =>
    store.dispatch('updateUISettings', {
      uiSettings: { ...uiSettings.value, chat_background_uploads: lista },
    });

  const claridadeSalva = computed(() => {
    const valor = uiSettings.value?.chat_background_brightness;
    return Number.isFinite(+valor) && valor !== '' ? +valor : CLARIDADE_PADRAO;
  });

  const aplicarVisual = ({ tema, fundo, claridade }) => {
    if (tema !== undefined) aplicaTemaPersonalizado(tema);
    if (fundo !== undefined) aplicaFundoDoChat(fundo);
    if (claridade !== undefined) aplicaClaridadeDoFundo(claridade);
  };

  const salvarPreferencias = ({ tema, fundo, claridade }) =>
    store.dispatch('updateUISettings', {
      uiSettings: {
        ...uiSettings.value,
        custom_theme: tema || '',
        chat_background: fundo || '',
        chat_background_brightness: claridade ?? CLARIDADE_PADRAO,
      },
    });

  // as ui_settings chegam depois do primeiro render (vêm com o perfil), então a aplicação
  // acompanha o valor em vez de acontecer uma vez só no boot
  const acompanharPreferencias = () => {
    // a escala da cor depende do tema, e o tema é decidido em outro ponto do carregamento
    vigiaTrocaDeTema();
    watch(
      [temaPersonalizadoSalvo, fundoDaConversaSalvo, claridadeSalva],
      ([tema, fundo, claridade]) => aplicarVisual({ tema, fundo, claridade }),
      { immediate: true }
    );
  };

  return {
    envios,
    registrarEnvios,
    temaPersonalizadoSalvo,
    fundoDaConversaSalvo,
    claridadeSalva,
    aplicarVisual,
    salvarPreferencias,
    acompanharPreferencias,
  };
}
