require 'rails_helper'

# Criar, editar e apagar modelo pela tela. O modelo vive na Meta, então o que importa aqui é quem
# pode chamar, qual caixa alcança a API e se o erro da Meta chega acionável ao usuário.
RSpec.describe 'Modelos de mensagem da caixa', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:base) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}" }
  let(:waba) { channel.provider_config['business_account_id'] }
  let(:templates_url) { "https://graph.facebook.com/v22.0/#{waba}/message_templates" }

  let(:payload) do
    {
      name: 'aviso_pagamento',
      language: 'pt_BR',
      category: 'UTILITY',
      body: 'Ola {{1}}, a reserva vence amanha.',
      examples: { '1' => 'Ana Souza' }
    }
  end

  before do
    # Sem fixar a base, um WHATSAPP_CLOUD_BASE_URL no ambiente muda a URL que o serviço chama.
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('WHATSAPP_CLOUD_BASE_URL', anything).and_return('https://graph.facebook.com')

    # Toda operação sincroniza no fim. Atender a leitura com WebMock, em vez de stubar o método,
    # mantém o caminho real rodando.
    stub_request(:get, %r{/message_templates}).to_return(status: 200, body: { data: [] }.to_json,
                                                         headers: { 'Content-Type' => 'application/json' })
  end

  describe 'POST create_message_template' do
    it 'cria o modelo e devolve o id da Meta' do
      stub_request(:post, templates_url).to_return(
        status: 200, body: { id: '999', status: 'PENDING', category: 'UTILITY' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      post "#{base}/create_message_template", params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq('999')
      expect(response.parsed_body['status']).to eq('PENDING')
    end

    it 'leva o exemplo que o usuario escreveu ate a Meta' do
      stub = stub_request(:post, templates_url)
             .with { |req| JSON.parse(req.body).dig('components', 0, 'example', 'body_text') == [['Ana Souza']] }
             .to_return(status: 200, body: { id: '999' }.to_json, headers: { 'Content-Type' => 'application/json' })

      post "#{base}/create_message_template", params: payload, headers: admin.create_new_auth_token, as: :json

      expect(stub).to have_been_requested
    end

    it 'exige administrador' do
      post "#{base}/create_message_template", params: payload, headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # 360dialog e Twilio não alcançam a API de modelos da Cloud.
    it 'recusa caixa que nao gerencia modelo' do
      outra = create(:channel_widget, account: account).inbox

      post "/api/v1/accounts/#{account.id}/inboxes/#{outra.id}/create_message_template",
           params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.whatsapp.templates.inbox_not_supported'))
    end

    # A explicação da Meta é o que torna o erro acionável; genérico manda a pessoa adivinhar.
    it 'repassa a mensagem de erro da Meta' do
      stub_request(:post, templates_url).to_return(
        status: 400,
        body: { error: { message: 'Invalid', error_user_msg: 'Ja existe um modelo com esse nome.' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      post "#{base}/create_message_template", params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Ja existe um modelo com esse nome.')
    end

    it 'recusa corpo que termina em variavel antes de chamar a Meta' do
      post "#{base}/create_message_template", params: payload.merge(body: 'Seu pedido chegou {{1}}'),
                                              headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.whatsapp.templates.dangling_variable'))
      expect(WebMock).not_to have_requested(:post, templates_url)
    end
  end

  describe 'POST update_message_template' do
    let(:update_url) { 'https://graph.facebook.com/v22.0/777' }

    it 'edita o modelo pelo id' do
      stub = stub_request(:post, update_url).to_return(status: 200, body: { success: true }.to_json,
                                                       headers: { 'Content-Type' => 'application/json' })

      post "#{base}/update_message_template", params: payload.except(:category).merge(template_id: '777'),
                                              headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(stub).to have_been_requested
    end

    it 'exige administrador' do
      post "#{base}/update_message_template", params: { template_id: '777' }.merge(payload),
                                              headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE destroy_message_template' do
    it 'apaga pelo nome e pelo id' do
      stub = stub_request(:delete, "#{templates_url}?name=aviso_pagamento&hsm_id=777")
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      delete "#{base}/destroy_message_template", params: { name: 'aviso_pagamento', template_id: '777' },
                                                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(stub).to have_been_requested
    end

    it 'exige administrador' do
      delete "#{base}/destroy_message_template", params: { name: 'aviso_pagamento' },
                                                 headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
