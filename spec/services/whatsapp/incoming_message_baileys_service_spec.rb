require 'rails_helper'

describe Whatsapp::IncomingMessageBaileysService do
  let!(:channel) do
    create(:channel_whatsapp,
           phone_number: '+5527988982141',
           provider: 'baileys',
           provider_config: { 'bridge_url' => 'http://whatsapp-baileys:3400', 'bridge_token' => 'segredo',
                              'webhook_verify_token' => 'web' },
           sync_templates: false,
           validate_provider_config: false)
  end

  # ⚠️ O id tem de ser único POR EXEMPLO: a deduplicação (Whatsapp::MessageDedupLock) vive no
  # Redis, que o rails_helper não limpa entre exemplos — um id fixo aqui faz o primeiro exemplo
  # travar todos os seguintes, e eles falham como se a mensagem não tivesse sido criada.
  let(:source_id) { "BAILEYS_#{SecureRandom.hex(6)}" }

  # Formato que a ponte entrega: o enxuto herdado do 360dialog, com `contacts` e `messages` na
  # raiz — sem o envelope entry/changes da Meta.
  let(:params) do
    {
      contacts: [{ wa_id: '5527999887766', profile: { name: 'Cliente Teste' } }],
      messages: [{ from: '5527999887766', id: source_id, timestamp: '1759670000',
                   type: 'text', text: { body: 'bom dia, queria saber da moto' } }]
    }.with_indifferent_access
  end

  it 'cria contato, conversa e mensagem na caixa do número' do
    described_class.new(inbox: channel.inbox, params: params).perform

    expect(channel.inbox.conversations.count).to eq(1)
    conversa = channel.inbox.conversations.last
    expect(conversa.contact.name).to eq('Cliente Teste')
    expect(conversa.contact.phone_number).to eq('+5527999887766')
    expect(conversa.messages.last.content).to eq('bom dia, queria saber da moto')
    expect(conversa.messages.last).to be_incoming
  end

  it 'guarda o id do WhatsApp para não duplicar a mensagem' do
    described_class.new(inbox: channel.inbox, params: params).perform

    expect(channel.inbox.messages.incoming.last.source_id).to eq(source_id)
  end

  # A ponte pode reentregar o mesmo evento (reconexão, retentativa de rede). Sem isso a conversa
  # ficaria com a mensagem repetida.
  it 'ignora a reentrega do mesmo evento' do
    described_class.new(inbox: channel.inbox, params: params).perform
    described_class.new(inbox: channel.inbox, params: params).perform

    expect(channel.inbox.messages.where(source_id: source_id).count).to eq(1)
  end

  # Quando o cliente responde citando, o Chatwoot liga a resposta à mensagem citada — e o painel
  # desenha a citação em cima da mensagem.
  describe 'resposta citada' do
    it 'liga a resposta à mensagem que ela cita' do
      described_class.new(inbox: channel.inbox, params: params).perform
      citada = channel.inbox.messages.incoming.last

      resposta = params.deep_dup
      resposta[:messages][0][:id] = "#{source_id}_resp"
      resposta[:messages][0][:text][:body] = 'e quanto custa?'
      # `context.id` é o que a ponte preenche a partir do contextInfo do Baileys, e é o mesmo campo
      # que a Meta manda na API oficial.
      resposta[:messages][0][:context] = { id: source_id }

      described_class.new(inbox: channel.inbox, params: resposta).perform

      nova = channel.inbox.messages.incoming.last
      expect(nova.content).to eq('e quanto custa?')
      expect(nova.content_attributes['in_reply_to']).to eq(citada.id)
      expect(nova.content_attributes['in_reply_to_external_id']).to eq(source_id)
    end

    # O cliente pode citar uma mensagem antiga que não está nesta conversa (ou que nunca chegou ao
    # Chatwoot). O callback `ensure_in_reply_to` resolve o id contra as mensagens da conversa e
    # grava nulo quando não acha — a mensagem tem de entrar assim mesmo, sem a citação.
    it 'entrega a mensagem mesmo citando algo que o Chatwoot não conhece' do
      resposta = params.deep_dup
      resposta[:messages][0][:context] = { id: 'MENSAGEM_QUE_NAO_TEMOS' }

      described_class.new(inbox: channel.inbox, params: resposta).perform

      nova = channel.inbox.messages.incoming.last
      expect(nova.content).to eq('bom dia, queria saber da moto')
      expect(nova.content_attributes['in_reply_to']).to be_nil
    end
  end

  it 'usa a conversa que já está aberta com o mesmo contato' do
    described_class.new(inbox: channel.inbox, params: params).perform
    segunda = params.deep_dup
    segunda[:messages][0][:id] = "#{source_id}_2"
    segunda[:messages][0][:text][:body] = 'e o valor da parcela?'

    described_class.new(inbox: channel.inbox, params: segunda).perform

    expect(channel.inbox.conversations.count).to eq(1)
    expect(channel.inbox.conversations.last.messages.incoming.count).to eq(2)
  end
end
