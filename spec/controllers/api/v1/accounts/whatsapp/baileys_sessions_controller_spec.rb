require 'rails_helper'

RSpec.describe 'Conexão do WhatsApp por QR code', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:ponte) { 'http://ponte:3400' }
  let(:numero) { '5527988982141' }
  let(:sessao) { 's-abc123' }

  before do
    create(:installation_config, name: 'BAILEYS_BRIDGE_URL', value: ponte)
    create(:installation_config, name: 'BAILEYS_BRIDGE_TOKEN', value: 'segredo-da-ponte')
    create(:installation_config, name: 'BAILEYS_BRIDGE_WEBHOOK_TOKEN', value: 'segredo-do-webhook')
    GlobalConfig.clear_cache
  end

  describe 'POST baileys/sessions' do
    # Sem número: quem pareia só descobre o número ao ler o QR, e a sessão o informa de volta.
    it 'abre a sessão na ponte sem exigir o número e devolve o id dela' do
      stub_request(:post, "#{ponte}/sessions")
        .with(headers: { 'X-Bridge-Token' => 'segredo-da-ponte' })
        .to_return(status: 200, body: { id: sessao, whatsapp_connection: 'waiting_qr' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(sessao)
    end

    # O segredo da ponte fica no servidor: se o painel pudesse falar direto com ela, qualquer
    # pessoa com acesso ao navegador mandaria WhatsApp por qualquer número.
    it 'exige administrador' do
      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions",
           headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa quando a ponte não está configurada' do
      InstallationConfig.find_by(name: 'BAILEYS_BRIDGE_URL').update!(value: '')
      GlobalConfig.clear_cache

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'avisa quando a ponte está fora do ar, em vez de estourar' do
      stub_request(:post, "#{ponte}/sessions").to_timeout

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe 'GET baileys/sessions/:session_id/qr' do
    # 202 significa "o QR ainda não saiu": a tela entende isso e volta a perguntar, em vez de
    # mostrar erro para quem está com o celular na mão esperando.
    it 'repassa o 202 de QR ainda não gerado' do
      stub_request(:get, "#{ponte}/sessions/#{sessao}/qr?format=text")
        .to_return(status: 202, body: { status: 'connecting' }.to_json, headers: { 'Content-Type' => 'application/json' })

      get "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions/#{sessao}/qr",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:accepted)
    end

    it 'devolve o QR como texto para o painel desenhar' do
      stub_request(:get, "#{ponte}/sessions/#{sessao}/qr?format=text")
        .to_return(status: 200, body: { status: 'waiting_qr', qr: '2@abc' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      get "/api/v1/accounts/#{account.id}/whatsapp/baileys/sessions/#{sessao}/qr",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['qr']).to eq('2@abc')
    end
  end

  describe 'POST baileys/connect' do
    def stub_sessao(connection:, number: nil)
      stub_request(:get, "#{ponte}/sessions/#{sessao}/health")
        .to_return(status: 200,
                   body: { whatsapp_connection: connection, whatsapp_number: number }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    # O número da caixa vem do pareamento, não do formulário.
    it 'cria a caixa com o número que a sessão pareou' do
      stub_sessao(connection: 'connected', number: numero)

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/connect",
           params: { session_id: sessao, name: 'Vendas' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      inbox = account.inboxes.find(response.parsed_body['id'])
      expect(inbox.name).to eq('Vendas')
      expect(inbox.channel.phone_number).to eq("+#{numero}")
      expect(inbox.channel.provider).to eq('baileys')
      expect(inbox.channel.provider_config['session_id']).to eq(sessao)
      expect(inbox.channel.provider_config['webhook_verify_token']).to eq('segredo-do-webhook')
    end

    # Criar a caixa antes de escanear deixaria uma caixa apontando para sessão que nunca conecta.
    it 'recusa enquanto a sessão não pareou' do
      stub_sessao(connection: 'waiting_qr')

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/connect",
           params: { session_id: sessao, name: 'Vendas' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.inboxes.count).to eq(0)
    end
  end
end
