require 'rails_helper'

describe ConversationBuilder do
  let(:account) { create(:account) }
  let!(:sms_channel) { create(:channel_sms, account: account) }
  let!(:api_channel) { create(:channel_api, account: account) }
  let!(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }
  let!(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_sms_inbox) { create(:contact_inbox, contact: contact, inbox: sms_inbox) }
  let(:contact_api_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox) }

  describe '#perform' do
    it 'creates sms conversation' do
      conversation = described_class.new(
        contact_inbox: contact_sms_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
    end

    it 'creates api conversation' do
      conversation = described_class.new(
        contact_inbox: contact_api_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
    end

    context 'when lock_to_single_conversation is true for sms inbox' do
      before do
        sms_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates sms conversation when existing conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
      end

      it 'returns last from existing sms conversations when existing conversation is not present' do
        create(:conversation, contact_inbox: contact_sms_inbox)
        existing_conversation = create(:conversation, contact_inbox: contact_sms_inbox)
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end

    context 'when lock_to_single_conversation is true for api inbox' do
      before do
        api_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates conversation when existing api conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
      end

      it 'returns last from existing api conversations when existing conversation is not present' do
        create(:conversation, contact_inbox: contact_api_inbox)
        existing_conversation = create(:conversation, contact_inbox: contact_api_inbox)
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end

    # Nosso: no WhatsApp o cliente ve um fio so, entao disparar um template pelo painel para quem
    # ja esta em atendimento tem que cair na conversa existente, e nao abrir uma segunda ao vivo.
    describe 'numa caixa de WhatsApp' do
      let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
      let!(:whatsapp_inbox) { create(:inbox, channel: whatsapp_channel, account: account) }
      let(:contact_whatsapp_inbox) { create(:contact_inbox, contact: contact, inbox: whatsapp_inbox) }

      def construir
        described_class.new(contact_inbox: contact_whatsapp_inbox, params: {}).perform
      end

      it 'usa a conversa que ja esta em atendimento' do
        em_andamento = create(:conversation, contact_inbox: contact_whatsapp_inbox, status: :open)

        expect(construir.id).to eq(em_andamento.id)
      end

      it 'usa tambem a conversa que esta com o bot' do
        com_bot = create(:conversation, contact_inbox: contact_whatsapp_inbox, status: :pending)

        expect(construir.id).to eq(com_bot.id)
      end

      it 'abre conversa nova quando a anterior ja foi resolvida' do
        resolvida = create(:conversation, contact_inbox: contact_whatsapp_inbox, status: :resolved)

        expect(construir.id).not_to eq(resolvida.id)
      end

      it 'abre conversa nova quando nao ha nenhuma' do
        expect(construir.contact_inbox_id).to eq(contact_whatsapp_inbox.id)
      end
    end
  end
end
