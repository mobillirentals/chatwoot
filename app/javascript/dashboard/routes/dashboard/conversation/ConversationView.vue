<script>
import { mapGetters } from 'vuex';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import MessageFilterPanel from 'dashboard/components/widgets/conversation/MessageFilterPanel.vue';
import { TOGGLE_MESSAGE_FILTER } from 'dashboard/constants/appEvents';

export default {
  components: {
    ChatList,
    ConversationBox,
    CmdBarConversationSnooze,
    SidepanelSwitch,
    ConversationSidebar,
    MessageFilterPanel,
  },
  beforeRouteLeave(to, from, next) {
    // Clear selected state if navigating away from a conversation to a route without a conversationId to prevent stale data issues
    // and resolves timing issues during navigation with conversation view and other screens
    if (this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
    next(); // Continue with navigation
  },
  props: {
    inboxId: {
      type: [String, Number],
      default: 0,
    },
    conversationId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    teamId: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
  },
  setup() {
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();

    return {
      uiSettings,
      updateUISettings,
      accountId,
    };
  },
  data() {
    return {
      showSearchModal: false,
      // Pesquisa dentro da conversa. Mora aqui, e nao no ConversationBox, para ficar no mesmo
      // nivel dos paineis nativos (Contato e Copilot): dentro do Box, o comutador flutuante
      // passava por cima dela.
      mostrarFiltroDeMensagens: false,
      periodoDoFiltro: null,
      lateralAntesDoFiltro: null,
    };
  },
  computed: {
    ...mapGetters({
      chatList: 'getAllConversations',
      currentChat: 'getSelectedChat',
    }),
    // Contato e Copilot dividem o mesmo espaco a direita; para a pesquisa tanto faz qual deles
    lateralDireitaAberta() {
      return Boolean(
        this.uiSettings?.is_contact_sidebar_open ||
          this.uiSettings?.is_copilot_panel_open
      );
    },
    showConversationList() {
      return this.isOnExpandedLayout ? !this.conversationId : true;
    },
    showMessageView() {
      return this.conversationId ? true : !this.isOnExpandedLayout;
    },
    isOnExpandedLayout() {
      const {
        LAYOUT_TYPES: { CONDENSED },
      } = wootConstants;
      const { conversation_display_type: conversationDisplayType = CONDENSED } =
        this.uiSettings;
      return conversationDisplayType !== CONDENSED;
    },

    shouldShowSidebar() {
      if (!this.currentChat.id) {
        return false;
      }

      const { is_contact_sidebar_open: isContactSidebarOpen } = this.uiSettings;
      return isContactSidebarOpen;
    },
  },
  watch: {
    conversationId() {
      this.fetchConversationIfUnavailable();
      // trocar de conversa nao leva o filtro da anterior junto
      this.periodoDoFiltro = null;
      this.fecharFiltroDeMensagens();
    },
    // abrir Contato ou Copilot tira a pesquisa da frente. Aqui NAO se restaura nada: a escolha
    // acabou de ser do usuario, e devolver o estado anterior a desfaria.
    lateralDireitaAberta(aberta) {
      if (!aberta || !this.mostrarFiltroDeMensagens) return;

      this.lateralAntesDoFiltro = null;
      this.mostrarFiltroDeMensagens = false;
    },
  },

  created() {
    // Clear selected state early if no conversation is selected
    // This prevents child components from accessing stale data
    // and resolves timing issues during navigation
    // with conversation view and other screens
    if (!this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
  },

  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('portals/index');
    emitter.on(TOGGLE_MESSAGE_FILTER, this.alternarFiltroDeMensagens);
    this.initialize();
    this.$watch('$store.state.route', () => this.initialize());
    this.$watch('chatList.length', () => {
      this.setActiveChat();
    });
  },

  beforeUnmount() {
    emitter.off(TOGGLE_MESSAGE_FILTER, this.alternarFiltroDeMensagens);
  },

  methods: {
    alternarFiltroDeMensagens() {
      if (this.mostrarFiltroDeMensagens) {
        this.fecharFiltroDeMensagens();
        return;
      }
      // Contato e Copilot saem da frente: com a pesquisa aberta seriam tres colunas, e a conversa
      // — que e o que importa — ficaria espremida. O estado volta quando a pesquisa fecha.
      this.lateralAntesDoFiltro = {
        contato: Boolean(this.uiSettings?.is_contact_sidebar_open),
        copilot: Boolean(this.uiSettings?.is_copilot_panel_open),
      };
      this.updateUISettings({
        is_contact_sidebar_open: false,
        is_copilot_panel_open: false,
      });
      this.mostrarFiltroDeMensagens = true;
    },
    fecharFiltroDeMensagens() {
      this.mostrarFiltroDeMensagens = false;
      if (!this.lateralAntesDoFiltro) return;

      this.updateUISettings({
        is_contact_sidebar_open: this.lateralAntesDoFiltro.contato,
        is_copilot_panel_open: this.lateralAntesDoFiltro.copilot,
      });
      this.lateralAntesDoFiltro = null;
    },
    onConversationLoad() {
      this.fetchConversationIfUnavailable();
    },
    initialize() {
      this.$store.dispatch('setActiveInbox', this.inboxId);
      this.setActiveChat();
    },
    toggleConversationLayout() {
      const { LAYOUT_TYPES } = wootConstants;
      const {
        conversation_display_type:
          conversationDisplayType = LAYOUT_TYPES.CONDENSED,
      } = this.uiSettings;
      const newViewType =
        conversationDisplayType === LAYOUT_TYPES.CONDENSED
          ? LAYOUT_TYPES.EXPANDED
          : LAYOUT_TYPES.CONDENSED;
      this.updateUISettings({
        conversation_display_type: newViewType,
        previously_used_conversation_display_type: newViewType,
      });
    },
    fetchConversationIfUnavailable() {
      if (!this.conversationId) {
        return;
      }
      const chat = this.findConversation();
      if (!chat) {
        this.$store.dispatch('getConversation', this.conversationId);
      }
    },
    findConversation() {
      const conversationId = parseInt(this.conversationId, 10);
      const [chat] = this.chatList.filter(c => c.id === conversationId);
      return chat;
    },
    setActiveChat() {
      if (this.conversationId) {
        const selectedConversation = this.findConversation();
        // If conversation doesn't exist or selected conversation is same as the active
        // conversation, don't set active conversation.
        if (
          !selectedConversation ||
          selectedConversation.id === this.currentChat.id
        ) {
          return;
        }
        const { messageId } = this.$route.query;
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
          });
      } else {
        this.$store.dispatch('clearSelectedState');
      }
    },
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
  },
};
</script>

<template>
  <section class="flex w-full h-full min-w-0">
    <ChatList
      :show-conversation-list="showConversationList"
      :conversation-inbox="inboxId"
      :label="label"
      :team-id="teamId"
      :conversation-type="conversationType"
      :folders-id="foldersId"
      :is-on-expanded-layout="isOnExpandedLayout"
      @conversation-load="onConversationLoad"
    />
    <ConversationBox
      v-if="showMessageView"
      :inbox-id="inboxId"
      :is-on-expanded-layout="isOnExpandedLayout"
      :periodo="periodoDoFiltro"
      @limpar-periodo="periodoDoFiltro = null"
    >
      <SidepanelSwitch v-if="currentChat.id" />
    </ConversationBox>
    <!-- irmao dos paineis nativos, e nao filho do ConversationBox: e o que evita o comutador
         flutuante passar por cima dele -->
    <MessageFilterPanel
      v-if="mostrarFiltroDeMensagens && currentChat.id"
      :conversation-id="currentChat.id"
      :periodo-ativo="periodoDoFiltro"
      @aplicar-periodo="periodoDoFiltro = $event"
      @close="fecharFiltroDeMensagens"
    />
    <ConversationSidebar v-if="shouldShowSidebar" :current-chat="currentChat" />
    <CmdBarConversationSnooze />
  </section>
</template>
