require 'rails_helper'

RSpec.describe Whatsapp::TemplateManagementService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              provider_config: { 'api_key' => 'test_key', 'phone_number_id' => 'random_id',
                                                 'business_account_id' => 'waba_123' })
  end
  let(:service) { described_class.new(channel: channel) }

  # As URLs saem do próprio canal: a factory define o provider_config e fixar valores aqui faria o
  # spec passar contra um endereço que o código não usa.
  let(:base) do
    version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
    "https://graph.facebook.com/#{version}"
  end
  let(:templates_url) { "#{base}/#{channel.provider_config['business_account_id']}/message_templates" }

  let(:atributos) do
    {
      name: 'aviso_pagamento',
      language: 'pt_BR',
      category: 'UTILITY',
      header: 'Mobilli Rentals',
      body: 'Ola {{1}}, a reserva {{2}} vence amanha.',
      examples: { '1' => 'Ana Souza', '2' => '4821' },
      footer: 'Equipe Mobilli',
      buttons: [{ type: 'QUICK_REPLY', text: 'Ja paguei' },
                { type: 'URL', text: 'Pagar', url: 'https://mobillirentals.com.br' }]
    }
  end

  before do
    # Sem fixar a base, um WHATSAPP_CLOUD_BASE_URL no ambiente muda a URL e o spec passa a testar
    # outro endereço que não o da Meta.
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('WHATSAPP_CLOUD_BASE_URL', anything).and_return('https://graph.facebook.com')

    # A sincronização é efeito colateral de cada operação; aqui só importa que ela aconteça.
    allow(channel).to receive(:provider_service).and_return(instance_double(Whatsapp::Providers::WhatsappCloudService,
                                                                            sync_templates: true))
  end

  describe '#create' do
    before do
      stub_request(:post, templates_url).to_return(status: 200, body: { id: '123', status: 'PENDING', category: 'UTILITY' }.to_json,
                                                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'monta os componentes no formato que a Meta espera' do
      service.create(atributos)

      expect(WebMock).to(have_requested(:post, templates_url).with do |req|
        corpo = JSON.parse(req.body)
        componentes = corpo['components']

        corpo['name'] == 'aviso_pagamento' &&
          corpo['language'] == 'pt_BR' &&
          corpo['category'] == 'UTILITY' &&
          componentes.map { |c| c['type'] } == %w[HEADER BODY FOOTER BUTTONS] &&
          componentes.first['format'] == 'TEXT' &&
          componentes.last['buttons'].map { |b| b['type'] } == %w[QUICK_REPLY URL]
      end)
    end

    # A Meta exige exemplo para cada variável e lê esse valor na análise.
    it 'envia o exemplo que o usuario escreveu' do
      service.create(atributos)

      expect(WebMock).to(have_requested(:post, templates_url).with do |req|
        corpo = JSON.parse(req.body).dig('components', 1, 'example', 'body_text')
        corpo == [['Ana Souza', '4821']]
      end)
    end

    it 'cai num exemplo generico quando a variavel ficou sem valor' do
      service.create(atributos.merge(examples: {}))

      expect(WebMock).to(have_requested(:post, templates_url).with do |req|
        JSON.parse(req.body).dig('components', 1, 'example', 'body_text') == [['exemplo 1', 'exemplo 2']]
      end)
    end

    it 'devolve o id e o status do modelo criado' do
      expect(service.create(atributos)).to eq({ id: '123', status: 'PENDING', category: 'UTILITY' })
    end

    it 'sincroniza para a lista nao ficar velha ate a varredura' do
      expect(channel.provider_service).to receive(:sync_templates)

      service.create(atributos)
    end

    it 'recusa nome fora do formato da Meta' do
      expect { service.create(atributos.merge(name: 'Nome Invalido')) }
        .to raise_error(described_class::Error, I18n.t('errors.whatsapp.templates.name_format'))
    end

    it 'recusa categoria que esta tela nao cria' do
      expect { service.create(atributos.merge(category: 'AUTHENTICATION')) }
        .to raise_error(described_class::Error, I18n.t('errors.whatsapp.templates.category_not_supported'))
    end

    it 'recusa corpo vazio' do
      expect { service.create(atributos.merge(body: '')) }
        .to raise_error(described_class::Error, I18n.t('errors.whatsapp.templates.body_required'))
    end

    # "dangling parameter": a Meta recusa corpo que comeca ou termina com variavel.
    it 'recusa variavel pendurada no comeco e no fim' do
      ['{{1}}, seu pedido chegou', 'Seu pedido chegou {{1}}'].each do |texto|
        expect { service.create(atributos.merge(body: texto)) }
          .to raise_error(described_class::Error, I18n.t('errors.whatsapp.templates.dangling_variable'))
      end
    end

    it 'recusa variavel no rodape' do
      expect { service.create(atributos.merge(footer: 'Equipe {{1}}')) }
        .to raise_error(described_class::Error, I18n.t('errors.whatsapp.templates.footer_no_variables'))
    end

    it 'recusa botao de link sem endereco' do
      botoes = [{ type: 'URL', text: 'Pagar' }]

      expect { service.create(atributos.merge(buttons: botoes)) }
        .to raise_error(described_class::Error, I18n.t('errors.whatsapp.templates.button_url_required'))
    end

    it 'recusa corpo acima do limite da Meta' do
      expect { service.create(atributos.merge(body: "Ola #{'a' * 1025}")) }
        .to raise_error(described_class::Error, /1024/)
    end

    # A Meta devolve a explicação em error_user_msg; repassar isso é o que deixa o erro acionável.
    it 'repassa a mensagem de erro da Meta' do
      stub_request(:post, templates_url).to_return(
        status: 400,
        body: { error: { message: 'Invalid parameter', error_user_msg: 'Ja existe um modelo com esse nome.' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      expect { service.create(atributos) }.to raise_error(described_class::Error, 'Ja existe um modelo com esse nome.')
    end
  end

  describe '#update' do
    let(:update_url) { "#{base}/555" }

    before do
      stub_request(:post, update_url).to_return(status: 200, body: { success: true }.to_json,
                                                headers: { 'Content-Type' => 'application/json' })
    end

    # A Meta não aceita trocar a categoria de um modelo aprovado: mandar de volta só cria chance
    # de recusa sem ganho nenhum.
    it 'nao envia a categoria quando ela nao foi informada' do
      service.update('555', atributos.except(:category))

      expect(WebMock).to(have_requested(:post, update_url).with { |req| !JSON.parse(req.body).key?('category') })
    end

    it 'envia so os componentes, sem nome nem idioma' do
      service.update('555', atributos.except(:category))

      expect(WebMock).to(have_requested(:post, update_url).with do |req|
        corpo = JSON.parse(req.body)
        corpo.keys == ['components'] && corpo['components'].map { |c| c['type'] } == %w[HEADER BODY FOOTER BUTTONS]
      end)
    end

    it 'sincroniza depois de editar' do
      expect(channel.provider_service).to receive(:sync_templates)

      service.update('555', atributos.except(:category))
    end
  end

  describe '#destroy' do
    it 'apaga pelo nome e pelo id do modelo' do
      stub = stub_request(:delete, "#{templates_url}?name=aviso_pagamento&hsm_id=555")
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.destroy('aviso_pagamento', '555')).to be(true)
      expect(stub).to have_been_requested
    end

    it 'apaga só pelo nome quando nao ha id' do
      stub = stub_request(:delete, "#{templates_url}?name=aviso_pagamento")
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      service.destroy('aviso_pagamento')

      expect(stub).to have_been_requested
    end

    it 'levanta erro quando a Meta recusa' do
      stub_request(:delete, /message_templates/).to_return(status: 404, body: { error: { message: 'Not found' } }.to_json,
                                                           headers: { 'Content-Type' => 'application/json' })

      expect { service.destroy('nao_existe') }.to raise_error(described_class::Error, 'Not found')
    end
  end
end
