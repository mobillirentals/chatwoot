require 'rails_helper'

describe Webhooks::WhatsappEventsJob do
  let!(:channel) do
    create(:channel_whatsapp, phone_number: '+5527988982141', provider: 'baileys',
                              provider_config: { 'bridge_url' => 'http://ponte:3400', 'bridge_token' => 'x',
                                                 'webhook_verify_token' => 'web' },
                              sync_templates: false, validate_provider_config: false)
  end

  it 'manda o payload da ponte para o serviço do baileys, não para o do 360dialog' do
    expect(Whatsapp::IncomingMessageBaileysService).to receive(:new).and_call_original
    expect(Whatsapp::IncomingMessageService).not_to receive(:new)

    described_class.perform_now(
      phone_number: channel.phone_number,
      contacts: [{ wa_id: '5527999887766', profile: { name: 'Cliente' } }],
      messages: [{ from: '5527999887766', id: "ROTA_#{SecureRandom.hex(6)}", timestamp: '1759670000', type: 'text',
                   text: { body: 'oi' } }]
    )
  end
end
