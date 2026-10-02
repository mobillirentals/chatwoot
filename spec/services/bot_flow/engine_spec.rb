# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BotFlow::Engine do
  describe '#hand_off_to_human' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
    let(:agente) { create(:user, account: account, role: :agent) }
    let(:time) { create(:team, account: account, name: 'pós-venda', allow_auto_assign: true) }
    # `pending` é como a conversa chega aqui de verdade: é o estado em que o bot atende, e é o
    # handoff que a abre. Criada já `open`, o rodízio atribuiria alguém na própria criação e o
    # teste passaria sem exercitar nada.
    let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }

    before do
      create(:inbox_member, inbox: inbox, user: agente)
      create(:team_member, team: time, user: agente)
      # o rodizio so sorteia entre quem esta online, e a presenca vive no Redis
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return(
        { agente.id.to_s => 'online' }
      )
    end

    def transferir
      described_class.new(conversation, 'atendente').send(:hand_off_to_human, 'pós-venda')
      conversation.reload
    end

    it 'poe a conversa na fila do time' do
      transferir

      expect(conversation.team).to eq(time)
      expect(conversation.status).to eq('open')
    end

    it 'escolhe um agente do time' do
      transferir

      expect(conversation.assignee).to eq(agente)
    end

    # O caso que motivou o teste: com o bot como responsavel, o Chatwoot pula a escolha de agente
    # (`return if ai_assignee_type.present?` no AssignmentHandler) e a conversa parava na fila do
    # time sem ninguem, mesmo com agente online. O bot precisa largar a conversa ao entregar.
    describe 'com o bot como responsavel pela conversa' do
      let(:bot) { create(:agent_bot, account: account) }

      before { conversation.update!(ai_assignee: bot) }

      it 'larga a conversa' do
        transferir

        expect(conversation.ai_assignee).to be_nil
        expect(conversation.assignee_agent_bot_id).to be_nil
      end

      it 'escolhe um agente do time mesmo assim' do
        transferir

        expect(conversation.assignee).to eq(agente)
      end
    end

    describe 'com um time que nao existe' do
      it 'abre a conversa sem atribuir time, em vez de estourar' do
        described_class.new(conversation, 'atendente').send(:hand_off_to_human, 'time inexistente')

        expect(conversation.reload.team).to be_nil
        expect(conversation.status).to eq('open')
      end
    end
  end
end
