require 'rails_helper'

# A rota de webhook do WhatsApp é pública, e para o provider baileys não existe assinatura da
# Meta para conferir (meta_signature_verification_required? já devolve false fora do
# whatsapp_cloud). Sem o token da ponte, qualquer um na internet poderia injetar mensagem como
# se fosse um cliente — é esse o buraco que estes exemplos guardam.
RSpec.describe 'Webhook da ponte Baileys', type: :request do
  let!(:channel) do
    create(:channel_whatsapp,
           phone_number: '+5527988982141',
           provider: 'baileys',
           provider_config: { 'bridge_url' => 'http://ponte:3400', 'bridge_token' => 'x',
                              'webhook_verify_token' => 'token-da-ponte' },
           sync_templates: false,
           validate_provider_config: false)
  end

  let(:payload) do
    {
      contacts: [{ wa_id: '5527999887766', profile: { name: 'Cliente' } }],
      messages: [{ from: '5527999887766', id: "W_#{SecureRandom.hex(6)}", timestamp: '1759670000',
                   type: 'text', text: { body: 'oi' } }]
    }
  end

  def postar(headers)
    post "/webhooks/whatsapp/#{channel.phone_number}", params: payload, headers: headers, as: :json
  end

  it 'aceita o webhook com o token da caixa' do
    expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)

    postar('X-Bridge-Token' => 'token-da-ponte')

    expect(response).to have_http_status(:success)
  end

  it 'recusa sem token' do
    expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)

    postar({})

    expect(response).to have_http_status(:unauthorized)
  end

  it 'recusa com token errado' do
    expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)

    postar('X-Bridge-Token' => 'chute')

    expect(response).to have_http_status(:unauthorized)
  end

  # Caixa salva sem o segredo não pode virar porta aberta: nesse caso recusa tudo, em vez de
  # aceitar qualquer requisição por não ter com o que comparar.
  it 'recusa quando a caixa está sem webhook_verify_token' do
    # a factory só desvia a validação no create; num update ela tentaria falar com a ponte
    channel.define_singleton_method(:validate_provider_config) { nil }
    channel.update!(provider_config: channel.provider_config.except('webhook_verify_token'))

    expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)

    postar('X-Bridge-Token' => 'token-da-ponte')

    expect(response).to have_http_status(:unauthorized)
  end

  # A verificação é só para baileys — uma caixa da API oficial continua no caminho da assinatura
  # da Meta, sem precisar de token nenhum.
  it 'não exige o token da ponte numa caixa 360dialog' do
    oficial = create(:channel_whatsapp, phone_number: '+5527900000000', provider: 'default',
                                        sync_templates: false, validate_provider_config: false)
    expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)

    post "/webhooks/whatsapp/#{oficial.phone_number}", params: payload, as: :json

    expect(response).to have_http_status(:success)
  end
end
