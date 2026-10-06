require 'rails_helper'

# Devolve o visto-azul ao cliente quando o agente abre a conversa no painel — outra coisa que a
# API oficial não permite.
RSpec.describe Whatsapp::MarkAsReadJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: account, contact_inbox: contact_inbox) }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+5527988982141', provider: 'baileys',
                              provider_config: { 'bridge_url' => 'http://ponte:3400', 'bridge_token' => 'x',
                                                 'webhook_verify_token' => 'web' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5527999887766') }
  let(:provider) { instance_double(Whatsapp::Providers::WhatsappBaileysService, marcar_como_lida: nil) }

  before { allow(Whatsapp::Providers::WhatsappBaileysService).to receive(:new).and_return(provider) }

  it 'manda a ponte marcar as mensagens daquele contato como lidas' do
    expect(provider).to receive(:marcar_como_lida).with('5527999887766')

    described_class.perform_now(conversation.id)
  end

  it 'não faz nada numa caixa da API oficial' do
    oficial = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    outra = create(:conversation, inbox: oficial.inbox, account: account)

    # `marcar_como_lida` só existe no provider da ponte — a verificação é que ele nem chega a ser
    # instanciado para uma caixa oficial.
    expect(provider).not_to receive(:marcar_como_lida)

    expect { described_class.perform_now(outra.id) }.not_to raise_error
  end

  # O job é enfileirado e roda depois: a conversa pode ter sido apagada nesse meio-tempo.
  it 'não quebra quando a conversa já não existe' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it 'não tenta marcar quando a conversa está sem contact_inbox' do
    sem_origem = create(:conversation, inbox: channel.inbox, account: account)
    # update_column porque source_id em branco não passa na validação da caixa de WhatsApp — e o
    # que importa aqui é o job aguentar o dado torto, não criar um dado válido.
    # rubocop:disable Rails/SkipsModelValidations
    sem_origem.contact_inbox.update_column(:source_id, '')
    # rubocop:enable Rails/SkipsModelValidations

    expect(provider).not_to receive(:marcar_como_lida)

    described_class.perform_now(sem_origem.id)
  end
end
