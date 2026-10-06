require 'rails_helper'

# Conexão de uma caixa que já existe: acompanhar o estado e reparear quando o aparelho é
# desconectado. Sem isso a caixa fica morta sem aviso, e só dá para reparear chamando a ponte na
# mão.
RSpec.describe 'Conexão de uma caixa da ponte Baileys', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ponte) { 'http://ponte:3400' }
  let(:numero) { '5527992962147' }
  let(:sessao) { 's-abc123' }

  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: "+#{numero}", provider: 'baileys',
                              provider_config: { 'bridge_url' => ponte, 'bridge_token' => 'x',
                                                 'webhook_verify_token' => 'web', 'session_id' => sessao },
                              sync_templates: false, validate_provider_config: false)
  end

  before do
    create(:installation_config, name: 'BAILEYS_BRIDGE_URL', value: ponte)
    create(:installation_config, name: 'BAILEYS_BRIDGE_TOKEN', value: 'segredo-da-ponte')
    create(:installation_config, name: 'BAILEYS_BRIDGE_WEBHOOK_TOKEN', value: 'segredo-do-webhook')
    GlobalConfig.clear_cache
  end

  describe 'GET baileys/inboxes/:inbox_id' do
    it 'devolve o estado da conexão daquela caixa' do
      stub_request(:get, "#{ponte}/sessions/#{sessao}/health")
        .to_return(status: 200,
                   body: { whatsapp_connection: 'connected', whatsapp_number: numero }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      get "/api/v1/accounts/#{account.id}/whatsapp/baileys/inboxes/#{channel.inbox.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['whatsapp_number']).to eq(numero)
    end

    # Caixas criadas antes de a sessão ganhar id próprio não têm session_id.
    it 'usa o número como sessão nas caixas antigas' do
      antiga = create(:channel_whatsapp, account: account, phone_number: '+5527988982141', provider: 'baileys',
                                         provider_config: { 'bridge_url' => ponte, 'bridge_token' => 'x',
                                                            'webhook_verify_token' => 'web' },
                                         sync_templates: false, validate_provider_config: false)
      stub_request(:get, "#{ponte}/sessions/5527988982141/health")
        .to_return(status: 200, body: { whatsapp_connection: 'connected' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      get "/api/v1/accounts/#{account.id}/whatsapp/baileys/inboxes/#{antiga.inbox.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    # Antes era o rescue genérico que pegava isso e devolvia 503 com texto de falha de envio.
    it 'devolve 404 para caixa que não é da ponte' do
      oficial = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                          sync_templates: false, validate_provider_config: false)

      get "/api/v1/accounts/#{account.id}/whatsapp/baileys/inboxes/#{oficial.inbox.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST baileys/inboxes/:inbox_id/reconnect' do
    # A trava vai junto: parear outro número faria a caixa seguir com o histórico e os contatos do
    # antigo, mas enviando de outro lugar — o cliente receberia resposta de um número que nunca
    # contatou.
    it 'manda reparear travando no número da caixa' do
      stub_request(:post, "#{ponte}/sessions/#{sessao}/repair")
        .with(body: { expected_number: numero }.to_json)
        .to_return(status: 200, body: { whatsapp_connection: 'waiting_qr', expected_number: numero }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/inboxes/#{channel.inbox.id}/reconnect",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['expected_number']).to eq(numero)
    end

    it 'repassa o aviso de número errado para a tela' do
      stub_request(:get, "#{ponte}/sessions/#{sessao}/health")
        .to_return(status: 200,
                   body: { whatsapp_connection: 'numero_errado',
                           wrong_number: { pareado: '5527996914255', esperado: numero } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      get "/api/v1/accounts/#{account.id}/whatsapp/baileys/inboxes/#{channel.inbox.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('wrong_number', 'pareado')).to eq('5527996914255')
    end

    it 'avisa quando a ponte está fora do ar, em vez de estourar' do
      stub_request(:post, "#{ponte}/sessions/#{sessao}/repair").to_timeout

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/inboxes/#{channel.inbox.id}/reconnect",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
    end

    it 'exige administrador' do
      agente = create(:user, account: account, role: :agent)

      post "/api/v1/accounts/#{account.id}/whatsapp/baileys/inboxes/#{channel.inbox.id}/reconnect",
           headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
