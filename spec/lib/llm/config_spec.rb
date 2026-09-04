require 'rails_helper'

RSpec.describe Llm::Config do
  before do
    described_class.reset!
    InstallationConfig.where(name: %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_OPEN_AI_ENDPOINT]).destroy_all
  end

  after do
    described_class.reset!
  end

  describe '.initialize!' do
    context 'when a custom endpoint is configured' do
      before do
        InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
        InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'https://example.cognitiveservices.azure.com/openai')
      end

      # O endpoint é guardado sem o `/v1`, que é parte da rota — quem chama acrescenta.
      # Sem isso, as chamadas globais do RubyLLM caíam em 404 no Azure OpenAI.
      it 'appends the /v1 route segment to the configured endpoint' do
        described_class.initialize!

        expect(RubyLLM.config.openai_api_base).to eq('https://example.cognitiveservices.azure.com/openai/v1')
      end

      it 'does not duplicate the separator when the endpoint has a trailing slash' do
        InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')
                          .update!(value: 'https://example.cognitiveservices.azure.com/openai/')

        described_class.initialize!

        expect(RubyLLM.config.openai_api_base).to eq('https://example.cognitiveservices.azure.com/openai/v1')
      end

      it 'configures the api key' do
        described_class.initialize!

        expect(RubyLLM.config.openai_api_key).to eq('test-key')
      end
    end

    context 'when no endpoint is configured' do
      before { InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key') }

      it 'leaves the api base untouched so RubyLLM uses its own default' do
        expect { described_class.initialize! }.not_to change(RubyLLM.config, :openai_api_base)
      end
    end
  end
end
