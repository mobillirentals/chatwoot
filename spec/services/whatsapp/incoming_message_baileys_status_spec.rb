require 'rails_helper'

# O Chatwoot já processa recibo de entrega e leitura (Messages::StatusUpdateService); a ponte só
# precisa entregar no formato `statuses`.
# rubocop:disable RSpec/DescribeClass -- descreve o comportamento, que atravessa job e servico
RSpec.describe 'recibo de entrega e leitura pela ponte' do
  let!(:channel) do
    create(:channel_whatsapp,
           phone_number: '+5527988982141',
           provider: 'baileys',
           provider_config: { 'bridge_url' => 'http://ponte:3400', 'bridge_token' => 'x',
                              'webhook_verify_token' => 'web' },
           sync_templates: false,
           validate_provider_config: false)
  end

  let(:source_id) { "ENV_#{SecureRandom.hex(6)}" }
  let!(:message) do
    conversa = create(:conversation, inbox: channel.inbox, account: channel.inbox.account)
    create(:message, conversation: conversa, inbox: channel.inbox, account: channel.inbox.account,
                     message_type: :outgoing, source_id: source_id, status: :sent)
  end

  def entregar(status)
    Whatsapp::IncomingMessageBaileysService.new(
      inbox: channel.inbox,
      params: { statuses: [{ id: source_id, status: status, timestamp: '1759670000' }] }.with_indifferent_access
    ).perform
  end

  it 'marca como entregue' do
    expect { entregar('delivered') }.to change { message.reload.status }.from('sent').to('delivered')
  end

  it 'marca como lida' do
    entregar('delivered')

    expect { entregar('read') }.to change { message.reload.status }.to('read')
  end

  it 'ignora recibo de mensagem que não é nossa' do
    outro = Whatsapp::IncomingMessageBaileysService.new(
      inbox: channel.inbox,
      params: { statuses: [{ id: 'NAO_EXISTE', status: 'read', timestamp: '1' }] }.with_indifferent_access
    )

    expect { outro.perform }.not_to(change { message.reload.status })
  end
end
# rubocop:enable RSpec/DescribeClass
