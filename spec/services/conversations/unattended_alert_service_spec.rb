require 'rails_helper'

# Cobre a regra de quem recebe o alerta interno (camada 2). As camadas 1 e 3 falam com o cliente e
# dependem da janela de 24h do WhatsApp; aqui o foco e a notificacao pra equipe.
RSpec.describe Conversations::UnattendedAlertService do
  let(:account) { create(:account) }
  let!(:admin_online) { create(:user, account: account, role: :administrator) }
  let!(:admin_offline) { create(:user, account: account, role: :administrator) }
  let(:assignee) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: assignee) }

  before do
    create(:inbox_member, user: assignee, inbox: inbox)
    # a conversa nasce com waiting_since do proprio callback; update_columns poe o passado sem
    # disparar os callbacks de novo
    # o passado precisa entrar sem passar pelos callbacks, que sao justamente quem acabou de
    # escrever o valor "agora"
    conversation.update_columns(waiting_since: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
    conversation.reload
  end

  def executa(available_users)
    described_class.new(conversation: conversation, agent_status: 'offline',
                        available_users: available_users).perform
  end

  describe 'quem recebe o alerta de conversa sem resposta' do
    it 'notifica apenas quem esta disponivel agora' do
      executa({ admin_online.id.to_s => 'online', admin_offline.id.to_s => 'offline' })

      expect(admin_online.notifications.count).to eq(1)
      expect(admin_offline.notifications.count).to eq(0)
    end

    it 'trata "busy" como disponivel: a pessoa segue na frente do computador' do
      executa({ admin_online.id.to_s => 'busy' })

      expect(admin_online.notifications.count).to eq(1)
    end

    it 'nao notifica ninguem quando todos estao fora' do
      executa({})

      expect(Notification.count).to eq(0)
    end

    it 'registra a nota privada na conversa mesmo sem ninguem pra notificar' do
      expect { executa({}) }.to change { conversation.messages.where(private: true).count }.by(1)
    end

    it 'sem informacao de presenca, mantem o comportamento antigo e avisa todos' do
      executa(nil)

      expect(admin_online.notifications.count).to eq(1)
      expect(admin_offline.notifications.count).to eq(1)
    end
  end
end
