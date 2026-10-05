require 'rails_helper'

describe Conversations::MessageWindowService do
  # A janela de 24h é regra da Meta. Aplicá-la num número que não passa pela Meta faria o envio
  # falhar dizendo que a janela fechou, sem que exista janela.
  it 'não impõe janela de 24h num canal baileys' do
    channel = create(:channel_whatsapp, phone_number: '+5527988982141', provider: 'baileys',
                                        provider_config: { 'bridge_url' => 'http://ponte:3400', 'bridge_token' => 'x' },
                                        sync_templates: false, validate_provider_config: false)
    conversa = create(:conversation, inbox: channel.inbox)
    create(:message, conversation: conversa, message_type: :incoming, created_at: 5.days.ago)

    expect(described_class.new(conversa).can_reply?).to be(true)
  end

  it 'continua impondo a janela de 24h no canal da API oficial' do
    channel = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    conversa = create(:conversation, inbox: channel.inbox)
    create(:message, conversation: conversa, message_type: :incoming, created_at: 5.days.ago)

    expect(described_class.new(conversa).can_reply?).to be(false)
  end
end
