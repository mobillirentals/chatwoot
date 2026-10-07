require 'rails_helper'

# O recado vive inteiro na Meta: aqui só se testa que falamos com ela do jeito certo e que o erro
# dela chega legível em quem chamou.
RSpec.describe Whatsapp::CallVoicemailService, type: :service do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              provider_config: { 'api_key' => 'segredo', 'phone_number_id' => '123',
                                                 'business_account_id' => '456' },
                              validate_provider_config: false, sync_templates: false)
  end
  let(:service) { described_class.new(channel: channel) }
  # A factory define o provider_config dela; derivar daqui evita um stub que casa por coincidência.
  let(:numero) { channel.provider_config['phone_number_id'] }
  let(:token) { channel.provider_config['api_key'] }
  let(:graph) { "https://graph.facebook.com/v22.0/#{numero}" }

  def arquivo
    StringIO.new('OggS-conteudo-falso')
  end

  describe '#fetch' do
    it 'devolve o recado configurado hoje' do
      stub_request(:get, "#{graph}/settings").to_return(
        status: 200,
        body: { calling: { status: 'ENABLED',
                           voicemail: { status: 'ENABLED', triggers: ['REJECT'],
                                        audio: { default: { announcement_media_id: '999' } } } } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      expect(service.fetch).to eq(
        'status' => 'ENABLED', 'triggers' => ['REJECT'],
        'audio' => { 'default' => { 'announcement_media_id' => '999' } }
      )
    end

    it 'devolve vazio quando nunca foi configurado' do
      stub_request(:get, "#{graph}/settings")
        .to_return(status: 200, body: { calling: { status: 'ENABLED' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(service.fetch).to eq({})
    end

    # Erro da Meta sem tradução vira "algo deu errado" na tela; com, o agente sabe o que fazer.
    it 'repassa a mensagem de erro da Meta' do
      stub_request(:get, "#{graph}/settings")
        .to_return(status: 400, body: { error: { error_user_msg: 'Número sem calling habilitado' } }.to_json)

      expect { service.fetch }.to raise_error(described_class::Error, 'Número sem calling habilitado')
    end
  end

  describe '#enable' do
    before do
      stub_request(:post, "#{graph}/media").to_return(
        status: 200, body: { id: '777' }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      stub_request(:post, "#{graph}/settings").to_return(
        status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
    end

    it 'envia o áudio com o use_case que a Meta exige para anúncio de recado' do
      service.enable(io: arquivo, filename: 'aviso.ogg')

      expect(a_request(:post, "#{graph}/media").with { |r| r.body.include?('call_voicemail_announcement') })
        .to have_been_made
    end

    it 'liga o recado apontando para o áudio recém-enviado' do
      service.enable(io: arquivo, filename: 'aviso.ogg')

      expect(a_request(:post, "#{graph}/settings").with(
               body: { calling: { voicemail: { status: 'ENABLED', triggers: ['REJECT'],
                                               audio: { default: { announcement_media_id: '777' } } } } }.to_json
             )).to have_been_made
    end

    # `timeout_seconds` só faz sentido com o gatilho TIMEOUT, e a Meta recusa fora de 0..30.
    it 'manda o tempo de espera apenas quando o gatilho TIMEOUT está presente' do
      service.enable(io: arquivo, filename: 'aviso.ogg', triggers: %w[REJECT TIMEOUT], timeout_seconds: 99)

      expect(a_request(:post, "#{graph}/settings").with { |r| r.body.include?('"timeout_seconds":30') })
        .to have_been_made
    end

    it 'ignora gatilho inventado e cai no REJECT' do
      service.enable(io: arquivo, filename: 'aviso.ogg', triggers: ['QUALQUER'])

      expect(a_request(:post, "#{graph}/settings").with { |r| r.body.include?('"triggers":["REJECT"]') })
        .to have_been_made
    end

    it 'não liga o recado quando o envio do áudio falha' do
      stub_request(:post, "#{graph}/media")
        .to_return(status: 400, body: { error: { message: 'Formato inválido' } }.to_json)

      expect { service.enable(io: arquivo, filename: 'aviso.ogg') }
        .to raise_error(described_class::Error, 'Formato inválido')
      expect(a_request(:post, "#{graph}/settings")).not_to have_been_made
    end
  end

  describe '#disable' do
    it 'desliga sem mexer em mais nada' do
      stub_request(:post, "#{graph}/settings").to_return(status: 200, body: { success: true }.to_json)

      service.disable

      expect(a_request(:post, "#{graph}/settings")
               .with(body: { calling: { voicemail: { status: 'DISABLED' } } }.to_json)).to have_been_made
    end
  end

  describe '#announcement_bytes' do
    # O áudio só sai da Meta com o token, que não pode ir ao navegador — por isso buscamos aqui.
    it 'baixa o áudio que está no ar' do
      stub_request(:get, "#{graph}/settings").to_return(
        status: 200,
        body: { calling: { voicemail: { status: 'ENABLED',
                                        audio: { default: { announcement_media_id: '999' } } } } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      stub_request(:get, 'https://graph.facebook.com/v22.0/999').to_return(
        status: 200, body: { url: 'https://lookaside.meta/audio' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      stub_request(:get, 'https://lookaside.meta/audio')
        .with(headers: { 'Authorization' => "Bearer #{token}" })
        .to_return(status: 200, body: 'bytes-do-ogg')

      expect(service.announcement_bytes).to eq('bytes-do-ogg')
    end

    it 'devolve nada quando não há recado configurado' do
      stub_request(:get, "#{graph}/settings")
        .to_return(status: 200, body: { calling: {} }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.announcement_bytes).to be_nil
    end
  end
end
