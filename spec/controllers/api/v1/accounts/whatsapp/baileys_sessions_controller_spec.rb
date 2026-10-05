require 'rails_helper'

RSpec.describe 'Conexão do WhatsApp por QR code', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:ponte) { 'http://ponte:3400' }
  let(:numero) { '5527988982141' }

  before do
    create(:installation_config, name: 'BAILEYS_BRIDGE_URL', value: ponte)
    create(:installation_config, name: 'BAILEYS_BRIDGE_TOKEN', value: 'segredo-da-ponte')
    create(:installation_config, name: 'BAILEYS_BRIDGE_WEBHOOK_TOKEN', value: 'segredo-do-webhook')
    GlobalConfig.clear_cache
  end

  describe 'POST baileys/sessions' do
    it 'abre a sessão na ponte e devolve o estado dela' do
      stub_request(:post, "#{ponte}/sessions")
        .with(body: { id: numero }.to_json, headers: { 'X-Bridge-Token' => 'segredo-da-ponte' })
        .to_return(status: 200, body: { id: numero, whatsapp_connection: 'waiting_qr' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions",
           params: { phone_number: '+55 27 98898-2141' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['whatsapp_connection']).to eq('waiting_qr')
    end

    # O segredo da ponte fica no servidor: se o painel pudesse falar direto com ela, qualquer
    # pessoa com acesso ao navegador mandaria WhatsApp por qualquer número.
    it 'exige administrador' do
      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions",
           params: { phone_number: numero }, headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa quando a ponte não está configurada' do
      InstallationConfig.find_by(name: 'BAILEYS_BRIDGE_URL').update!(value: '')
      GlobalConfig.clear_cache

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions",
           params: { phone_number: numero }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'avisa quando a ponte está fora do ar, em vez de estourar' do
      stub_request(:post, "#{ponte}/sessions").to_timeout

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions",
           params: { phone_number: numero }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe 'GET baileys/sessions/:phone_number/qr' do
    # 202 significa "o QR ainda não saiu": a tela entende isso e volta a perguntar, em vez de
    # mostrar erro para quem está com o celular na mão esperando.
    it 'repassa o 202 de QR ainda não gerado' do
      stub_request(:get, "#{ponte}/sessions/#{numero}/qr?format=text")
        .to_return(status: 202, body: { status: 'connecting' }.to_json, headers: { 'Content-Type' => 'application/json' })

      get "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions/#{numero}/qr",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:accepted)
    end

    it 'devolve o QR como texto para o painel desenhar' do
      stub_request(:get, "#{ponte}/sessions/#{numero}/qr?format=text")
        .to_return(status: 200, body: { status: 'waiting_qr', qr: '2@abc' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      get "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions/#{numero}/qr",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['qr']).to eq('2@abc')
    end
  end

  describe 'POST baileys/connect' do
    def stub_ponte_pareada_com(numero_pareado)
      stub_request(:get, "#{ponte}/sessions/#{numero}/health")
        .to_return(status: 200,
                   body: { whatsapp_connection: 'connected', whatsapp_number: numero_pareado }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'cria a caixa quando a ponte está pareada com aquele número' do
      stub_ponte_pareada_com(numero)

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/connect",
           params: { phone_number: numero, name: 'Vendas' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      inbox = account.inboxes.find(response.parsed_body['id'])
      expect(inbox.name).to eq('Vendas')
      expect(inbox.channel.provider).to eq('baileys')
      expect(inbox.channel.provider_config['webhook_verify_token']).to eq('segredo-do-webhook')
    end

    # A armadilha com mais de uma sessão no ar: apontar a caixa para a sessão errada mandaria
    # mensagem de outro número sem avisar ninguém.
    it 'recusa quando a ponte está pareada com outro número' do
      stub_ponte_pareada_com('5527992962147')

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/connect",
           params: { phone_number: numero, name: 'Vendas' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.inboxes.count).to eq(0)
    end
  end
end
