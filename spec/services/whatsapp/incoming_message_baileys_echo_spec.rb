require 'rails_helper'

# Mensagem que sai por fora do painel — atendente respondendo pelo aplicativo do celular, ou a
# resposta automática do WhatsApp Business — precisa aparecer na conversa. Sem isso o próximo
# atendente vê a pergunta do cliente e não vê o que já foi respondido.
# rubocop:disable RSpec/DescribeClass -- descreve o comportamento, que atravessa job e servico
RSpec.describe 'eco de mensagem enviada por fora do painel' do
  let!(:channel) do
    create(:channel_whatsapp,
           phone_number: '+5527988982141',
           provider: 'baileys',
           provider_config: { 'bridge_url' => 'http://ponte:3400', 'bridge_token' => 'x',
                              'webhook_verify_token' => 'web' },
           sync_templates: false,
           validate_provider_config: false)
  end

  let(:source_id) { "ECO_#{SecureRandom.hex(6)}" }

  # No eco os papéis se invertem: `from` é a empresa e `to` é o cliente — e é do `to` que sai o
  # contato.
  let(:params) do
    {
      contacts: [{ wa_id: '5527999887766' }],
      message_echoes: [{ from: '5527988982141', to: '5527999887766', id: source_id,
                         timestamp: '1759670000', type: 'text',
                         text: { body: 'respondi pelo celular' } }]
    }.with_indifferent_access
  end

  it 'grava como mensagem enviada, não como mensagem do cliente' do
    Whatsapp::IncomingMessageBaileysService.new(inbox: channel.inbox, params: params, outgoing_echo: true).perform

    msg = channel.inbox.messages.last
    expect(msg.content).to eq('respondi pelo celular')
    expect(msg).to be_outgoing
    expect(msg.sender).to be_nil
    expect(msg.content_attributes['external_echo']).to be(true)
  end

  it 'usa o destinatário como contato da conversa' do
    Whatsapp::IncomingMessageBaileysService.new(inbox: channel.inbox, params: params, outgoing_echo: true).perform

    expect(channel.inbox.conversations.last.contact.phone_number).to eq('+5527999887766')
  end

  # Já entregue: marcar como `sent` faria o SendReplyJob tentar enviar de novo pela ponte, e o
  # cliente receberia a mesma mensagem duas vezes.
  it 'nasce como entregue, para não ser reenviada' do
    Whatsapp::IncomingMessageBaileysService.new(inbox: channel.inbox, params: params, outgoing_echo: true).perform

    expect(channel.inbox.messages.last.status).to eq('delivered')
  end

  describe 'roteamento no job' do
    it 'reconhece o eco pelo formato enxuto da ponte e marca outgoing_echo' do
      expect(Whatsapp::IncomingMessageBaileysService).to receive(:new)
        .with(hash_including(outgoing_echo: true))
        .and_call_original

      Webhooks::WhatsappEventsJob.perform_now(params.merge(phone_number: channel.phone_number))
    end

    it 'não marca outgoing_echo numa mensagem comum do cliente' do
      comum = {
        phone_number: channel.phone_number,
        contacts: [{ wa_id: '5527999887766', profile: { name: 'Cliente' } }],
        messages: [{ from: '5527999887766', id: "C_#{SecureRandom.hex(6)}", timestamp: '1759670000',
                     type: 'text', text: { body: 'oi' } }]
      }

      expect(Whatsapp::IncomingMessageBaileysService).to receive(:new)
        .with(hash_excluding(outgoing_echo: true))
        .and_call_original

      Webhooks::WhatsappEventsJob.perform_now(comum.with_indifferent_access)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
