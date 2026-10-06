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

  # Uma chamada entra na conversa como mensagem do cliente, o que marca `waiting_since` e fazia o
  # alerta tratar a ligacao como alguem ignorado. O cliente que acabou de falar no telefone recebia
  # um texto dizendo que a equipe "ja viu sua mensagem e vai responder em breve".
  describe 'quando o que esta esperando e uma chamada' do
    # Chamada so existe em caixa de voz, e o payload do upstream le o telefone do canal: num
    # widget, montar o evento estoura.
    let(:channel) do
      create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false)
    end
    let(:inbox) { channel.inbox }

    def chamada!(status)
      mensagem = create(:message, account: account, inbox: inbox, conversation: conversation,
                                  message_type: :incoming, content_type: :voice_call)
      create(:call, account: account, inbox: inbox, conversation: conversation,
                    contact: conversation.contact, message: mensagem, status: status)
      conversation.update_columns(waiting_since: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      conversation.reload
    end

    # Nota interna da camada 2 tambem e `outgoing`; o que importa aqui e o que chega ao cliente.
    it 'nao manda mensagem ao cliente' do
      chamada!('no_answer')

      expect { executa({ assignee.id.to_s => 'online' }) }
        .not_to(change { conversation.messages.outgoing.where(private: false).count })
    end

    # Perdida deixa algo pendente: alguem precisa retornar.
    it 'ainda avisa os administradores quando a chamada foi perdida' do
      chamada!('no_answer')

      executa({ admin_online.id.to_s => 'online' })

      expect(admin_online.notifications.count).to eq(1)
    end

    # Atendida nao deixa nada pendente, nem para o cliente nem para quem administra.
    it 'nao avisa ninguem quando a chamada foi atendida' do
      chamada!('completed')

      executa({ admin_online.id.to_s => 'online' })

      expect(admin_online.notifications.count).to eq(0)
      expect(conversation.messages.outgoing.count).to eq(0)
      expect(conversation.messages.where(private: true).count).to eq(0)
    end

    # Texto depois da chamada volta a ser espera de verdade.
    it 'volta a alertar quando o cliente escreve depois da chamada' do
      chamada!('completed')
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :incoming, content: 'E aí, conseguiu ver?')
      conversation.update_columns(waiting_since: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      conversation.reload

      executa({ admin_online.id.to_s => 'online' })

      expect(admin_online.notifications.count).to eq(1)
    end
  end
end
