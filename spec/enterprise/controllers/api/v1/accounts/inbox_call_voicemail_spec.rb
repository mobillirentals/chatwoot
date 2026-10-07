require 'rails_helper'

# Os três endpoints do recado: ler, gravar e servir o áudio que está no ar. O áudio precisa passar
# pelo servidor porque só sai da Meta com o token, que não pode ir ao navegador.
RSpec.describe 'Recado de voz da chamada', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:numero) { channel.provider_config['phone_number_id'] }
  let(:graph) { "https://graph.facebook.com/v22.0/#{numero}" }
  let(:base) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}" }

  def stub_settings(voicemail)
    stub_request(:get, "#{graph}/settings").to_return(
      status: 200, body: { calling: { voicemail: voicemail }.compact }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  describe 'GET call_voicemail' do
    it 'devolve o recado configurado' do
      stub_settings({ status: 'ENABLED', triggers: ['REJECT'] })

      get "#{base}/call_voicemail", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('ENABLED')
    end

    # Mesma regra das ações irmãs de chamada: configurar caixa é coisa de administrador.
    it 'exige administrador' do
      get "#{base}/call_voicemail", headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa caixa que não suporta chamada' do
      outra = create(:channel_whatsapp, account: account, provider: 'default',
                                        validate_provider_config: false, sync_templates: false)

      get "/api/v1/accounts/#{account.id}/inboxes/#{outra.inbox.id}/call_voicemail",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Erro da Meta tem que chegar legível, senão vira "algo deu errado" na tela.
    it 'repassa a mensagem de erro da Meta' do
      stub_request(:get, "#{graph}/settings")
        .to_return(status: 400, body: { error: { error_user_msg: 'Calling desabilitado' } }.to_json)

      get "#{base}/call_voicemail", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Calling desabilitado')
    end
  end

  describe 'POST set_call_voicemail' do
    let(:audio) { fixture_file_upload(Rails.public_path.join('audio/widget/ding.mp3'), 'audio/ogg') }

    it 'envia o áudio e liga o recado' do
      stub_request(:post, "#{graph}/media").to_return(
        status: 200, body: { id: '777' }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      stub_request(:post, "#{graph}/settings").to_return(status: 200, body: { success: true }.to_json)
      stub_settings({ status: 'ENABLED', triggers: ['REJECT'] })

      post "#{base}/set_call_voicemail", params: { audio: audio }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('ENABLED')
    end

    it 'desliga sem exigir áudio' do
      stub_request(:post, "#{graph}/settings").to_return(status: 200, body: { success: true }.to_json)
      stub_settings({ status: 'DISABLED' })

      post "#{base}/set_call_voicemail", params: { disable: true }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('DISABLED')
    end

    it 'avisa quando nenhum arquivo foi escolhido' do
      post "#{base}/set_call_voicemail", params: {}, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('OGG')
    end

    it 'exige administrador' do
      post "#{base}/set_call_voicemail", params: { audio: audio }, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET call_voicemail_announcement' do
    it 'serve os bytes do áudio que está no ar' do
      stub_settings({ status: 'ENABLED', audio: { default: { announcement_media_id: '999' } } })
      stub_request(:get, 'https://graph.facebook.com/v22.0/999').to_return(
        status: 200, body: { url: 'https://lookaside.meta/audio' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      stub_request(:get, 'https://lookaside.meta/audio').to_return(status: 200, body: 'bytes-do-ogg')

      get "#{base}/call_voicemail_announcement", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.body).to eq('bytes-do-ogg')
      expect(response.media_type).to eq('audio/ogg')
    end

    # 204 em vez de erro: a tela só não mostra o player, sem alarmar ninguém.
    it 'devolve 204 quando não há recado' do
      stub_settings(nil)

      get "#{base}/call_voicemail_announcement", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:no_content)
    end
  end
end
