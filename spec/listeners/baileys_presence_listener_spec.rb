require 'rails_helper'

# Leva o "digitando..." do agente até o aparelho do cliente — coisa que a API oficial não permite,
# porque a Meta não expõe indicador de digitação.
RSpec.describe BaileysPresenceListener do
  let(:listener) { described_class.instance }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: account, contact_inbox: contact_inbox) }
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+5527988982141', provider: 'baileys',
                              provider_config: { 'bridge_url' => 'http://ponte:3400', 'bridge_token' => 'x',
                                                 'webhook_verify_token' => 'web' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5527999887766') }
  let(:provider) { instance_double(Whatsapp::Providers::WhatsappBaileysService, avisar_presenca: nil) }

  before { allow(Whatsapp::Providers::WhatsappBaileysService).to receive(:new).and_return(provider) }

  def evento(nome, dados = {})
    Events::Base.new(nome, Time.zone.now, { conversation: conversation, user: agente }.merge(dados))
  end

  it 'avisa a ponte que o agente começou a digitar' do
    expect(provider).to receive(:avisar_presenca).with('5527999887766', 'composing')

    listener.conversation_typing_on(evento('conversation.typing_on'))
  end

  it 'avisa quando o agente para de digitar' do
    expect(provider).to receive(:avisar_presenca).with('5527999887766', 'paused')

    listener.conversation_typing_off(evento('conversation.typing_off'))
  end

  # Nota privada é conversa interna da equipe: avisar "digitando" entregaria ao cliente que algo
  # está sendo escrito sobre ele, que ele nunca vai ver.
  it 'não avisa quando o agente está escrevendo uma nota privada' do
    expect(provider).not_to receive(:avisar_presenca)

    listener.conversation_typing_on(evento('conversation.typing_on', is_private: true))
  end

  # O cliente digitando no widget dispara o MESMO evento. Repassar isso diria ao cliente que ele
  # próprio está digitando.
  it 'não avisa quando quem digita é o contato, não o agente' do
    expect(provider).not_to receive(:avisar_presenca)

    listener.conversation_typing_on(evento('conversation.typing_on', user: conversation.contact))
  end

  it 'ignora conversa de caixa que não é da ponte' do
    oficial = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    outra = create(:conversation, inbox: oficial.inbox, account: account)

    # `avisar_presenca` só existe no provider da ponte — a verificação é que ele nem chega a ser
    # usado para uma caixa oficial.
    expect(provider).not_to receive(:avisar_presenca)

    expect do
      listener.conversation_typing_on(Events::Base.new('conversation.typing_on', Time.zone.now,
                                                       conversation: outra, user: agente))
    end.not_to raise_error
  end
end
