require 'rails_helper'

describe Whatsapp::Providers::WhatsappBaileysService do
  subject(:service) { described_class.new(whatsapp_channel: channel) }

  let(:bridge_url) { 'http://whatsapp-baileys:3400' }
  # A ponte atende varios numeros, um por sessao, e a sessao e o proprio numero da caixa.
  let(:sessao_url) { "#{bridge_url}/sessions/5527988982141" }
  let(:sessao_url_send) { "#{sessao_url}/send" }
  let(:sessao_url_health) { "#{sessao_url}/health" }
  let(:channel) do
    create(:channel_whatsapp,
           phone_number: '+5527988982141',
           provider: 'baileys',
           provider_config: { 'bridge_url' => bridge_url, 'bridge_token' => 'segredo', 'webhook_verify_token' => 'web' },
           sync_templates: false,
           validate_provider_config: false)
  end
  let(:message) { create(:message, message_type: :outgoing, content: 'oi', conversation: create(:conversation, inbox: channel.inbox)) }

  describe '#send_message' do
    it 'manda o texto para a ponte e devolve o id da mensagem' do
      stub_request(:post, sessao_url_send)
        .with(
          body: { to: '5527988982141', text: 'oi' }.to_json,
          headers: { 'X-Bridge-Token' => 'segredo' }
        )
        .to_return(status: 200, body: { status: 'ok', message_id: 'BAILEYS123' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.send_message('5527988982141', message)).to eq('BAILEYS123')
    end

    # Ponte fora do ar é o modo de falha mais comum (container parado, sessão caída). A mensagem
    # tem de ficar como falhada, senão o agente acha que o cliente recebeu.
    it 'marca a mensagem como falhada quando a ponte não responde' do
      stub_request(:post, sessao_url_send).to_timeout

      expect(service.send_message('5527988982141', message)).to be_nil
      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq(I18n.t('errors.whatsapp.baileys.bridge_unreachable'))
    end

    it 'marca a mensagem como falhada quando a sessão não está pareada' do
      stub_request(:post, sessao_url_send)
        .to_return(status: 503, body: { error: 'Sessao do WhatsApp ainda nao esta conectada' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(service.send_message('5527988982141', message)).to be_nil
      expect(message.reload.status).to eq('failed')
    end

    # Resposta citada: o painel grava qual mensagem está sendo respondida, e a ponte sabe citar.
    #
    # ⚠️ A mensagem citada tem de existir na conversa: o callback `ensure_in_reply_to` do Message
    # resolve o id contra as mensagens dela e grava nil quando não acha — citar um id solto não
    # guarda nada, e o teste passaria a verificar o nada.
    it 'repassa à ponte qual mensagem está sendo respondida' do
      create(:message, conversation: message.conversation, inbox: message.inbox, account: message.account,
                       message_type: :incoming, source_id: 'WA_ORIGINAL_99', content: 'pergunta do cliente')
      message.update!(content_attributes: { in_reply_to_external_id: 'WA_ORIGINAL_99' })
      stub_request(:post, sessao_url_send)
        .with(body: { to: '5527988982141', text: 'oi', quoted_id: 'WA_ORIGINAL_99' }.to_json)
        .to_return(status: 200, body: { status: 'ok', message_id: 'X1' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(service.send_message('5527988982141', message)).to eq('X1')
    end

    it 'não manda quoted_id quando a mensagem não responde a ninguém' do
      stub_request(:post, sessao_url_send)
        .with(body: { to: '5527988982141', text: 'oi' }.to_json)
        .to_return(status: 200, body: { status: 'ok', message_id: 'X2' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(service.send_message('5527988982141', message)).to eq('X2')
    end

    # Enviar só o texto e descartar o anexo em silêncio faria o agente acreditar que a foto foi.
    it 'recusa anexo em vez de mandar só o texto' do
      message.attachments.new(account_id: message.account_id, file_type: :image)
      message.save!

      expect(service.send_message('5527988982141', message)).to be_nil
      expect(message.reload.external_error).to eq(I18n.t('errors.whatsapp.baileys.attachment_unsupported'))
      expect(WebMock).not_to have_requested(:post, sessao_url_send)
    end
  end

  describe '#send_template' do
    it 'recusa, porque fora da API oficial não existe modelo aprovado' do
      expect(service.send_template('5527988982141', { name: 'qualquer' }, message)).to be_nil
      expect(message.reload.external_error).to eq(I18n.t('errors.whatsapp.baileys.template_unsupported'))
    end
  end

  describe '#validate_provider_config?' do
    it 'aceita quando a ponte está conectada com o número da caixa' do
      stub_health(connection: 'connected', number: '5527988982141')

      expect(service.validate_provider_config?).to be(true)
    end

    # A armadilha real: duas pontes no ar (esta e a de verificação de número). Apontar a caixa
    # para a sessão errada mandaria mensagem do outro número sem avisar ninguém.
    it 'recusa quando a ponte está pareada com outro número' do
      stub_health(connection: 'connected', number: '5527992962147')

      expect(service.validate_provider_config?).to be(false)
    end

    it 'recusa enquanto a sessão ainda não foi pareada' do
      stub_health(connection: 'waiting_qr', number: nil)

      expect(service.validate_provider_config?).to be(false)
    end

    it 'recusa quando a ponte está fora do ar' do
      stub_request(:get, sessao_url_health).to_timeout

      expect(service.validate_provider_config?).to be(false)
    end

    it 'recusa quando a caixa não tem bridge_url' do
      channel.provider_config = channel.provider_config.except('bridge_url')

      expect(service.validate_provider_config?).to be(false)
    end
  end

  describe '#sync_templates' do
    it 'não tem catálogo para buscar e só marca como atualizado' do
      expect { service.sync_templates }.to(change { channel.reload.message_templates_last_updated })
    end
  end

  def stub_health(connection:, number:)
    stub_request(:get, sessao_url_health)
      .to_return(
        status: 200,
        body: { status: 'ok', whatsapp_connection: connection, whatsapp_number: number }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
end
