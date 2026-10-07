require 'rails_helper'

RSpec.describe Llm::SpeechToTextService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }
  let(:service) { described_class.new(blob: attachment.file.blob, account: account) }

  before do
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_API_KEY') { |config| config.value = 'test-api-key' }
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_MODEL') { |config| config.value = 'gpt-4o-mini' }

    attachment.file.attach(
      io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
      filename: 'speech',
      content_type: 'audio/mpeg'
    )
  end

  describe '.available_for?' do
    before do
      allow(account).to receive(:usage_limits).and_return(
        {
          agents: ChatwootApp.max_limit,
          inboxes: ChatwootApp.max_limit,
          captain: { responses: { current_available: 100 } }
        }
      )
    end

    it 'is false when the captain_integration feature is disabled' do
      account.disable_features!('captain_integration')

      expect(described_class.available_for?(account)).to be(false)
    end

    it 'is false when audio transcriptions are disabled on the account' do
      account.enable_features!('captain_integration')
      account.update!(audio_transcriptions: false)

      expect(described_class.available_for?(account)).to be(false)
    end

    it 'is false when no captain responses are available' do
      account.enable_features!('captain_integration')
      allow(account).to receive(:usage_limits).and_return(captain: { responses: { current_available: 0 } })

      expect(described_class.available_for?(account)).to be(false)
    end

    it 'is true when the feature, setting and credits are all present' do
      account.enable_features!('captain_integration')

      expect(described_class.available_for?(account)).to be(true)
    end
  end

  describe '.too_large?' do
    it 'is false when the blob is missing' do
      expect(described_class.too_large?(nil)).to be(false)
    end

    it 'is true beyond the byte limit' do
      allow(attachment.file.blob).to receive(:byte_size).and_return(described_class::BYTE_LIMIT + 1)

      expect(described_class.too_large?(attachment.file.blob)).to be(true)
    end
  end

  describe '#fetch_audio_file' do
    it 'adds extension from content type when filename has no extension' do
      temp_file_path = service.send(:fetch_audio_file)

      expect(File.extname(temp_file_path)).to eq('.mpeg')
    ensure
      FileUtils.rm_f(temp_file_path) if temp_file_path.present?
    end
  end

  describe '#perform' do
    let(:audio_api) { double('audio_api') } # rubocop:disable RSpec/VerifiedDoubles
    let(:audio_file_path) { Rails.root.join('tmp/speech_to_text_service_spec.mp3').to_s }

    before do
      File.binwrite(audio_file_path, 'audio')
      allow(service).to receive(:fetch_audio_file).and_return(audio_file_path)
      allow(account).to receive(:increment_response_usage)
      allow(service.client).to receive(:audio).and_return(audio_api)
    end

    after do
      FileUtils.rm_f(audio_file_path)
    end

    it 'uses the audio transcription feature model' do
      expect(audio_api).to receive(:transcribe).with(
        parameters: hash_including(model: 'gpt-4o-mini-transcribe', temperature: 0.0)
      ).and_return({ 'text' => 'Audio transcript' })

      expect(service.perform).to eq('Audio transcript')
    end

    it 'consumes a captain response credit when text comes back' do
      allow(audio_api).to receive(:transcribe).and_return({ 'text' => 'Audio transcript' })

      service.perform

      expect(account).to have_received(:increment_response_usage)
    end

    it 'does not consume a credit when the transcription is blank' do
      allow(audio_api).to receive(:transcribe).and_return({ 'text' => '' })

      service.perform

      expect(account).not_to have_received(:increment_response_usage)
    end
  end

  # Saber QUANDO cada frase foi dita e o que permite a transcricao acompanhar o audio. So o whisper
  # devolve isso: os modelos novos recusam `verbose_json` com 400, testado contra o proprio recurso.
  describe '#perform com segmentos' do
    let(:service) { described_class.new(blob: attachment.file.blob, account: account, with_segments: true) }
    let(:audio_api) { double('audio_api') } # rubocop:disable RSpec/VerifiedDoubles
    let(:audio_file_path) { Rails.root.join('tmp/speech_to_text_segments_spec.mp3').to_s }
    let(:resposta) { { 'text' => 'Bom dia.', 'segments' => [{ 'start' => 0.0, 'end' => 1.0, 'text' => 'Bom dia.' }] } }

    before do
      File.binwrite(audio_file_path, 'audio')
      allow(service).to receive(:fetch_audio_file).and_return(audio_file_path)
      allow(account).to receive(:increment_response_usage)
      allow(service.client).to receive(:audio).and_return(audio_api)
      allow(audio_api).to receive(:transcribe).and_return(resposta)
    end

    after { FileUtils.rm_f(audio_file_path) }

    it 'devolve a resposta inteira, com os trechos e seus tempos' do
      expect(service.perform).to eq(resposta)
    end

    it 'pede verbose_json' do
      service.perform

      expect(audio_api).to have_received(:transcribe) do |parameters:|
        expect(parameters[:response_format]).to eq('verbose_json')
      end
    end

    # Sem informar o idioma, o whisper adivinha a cada trecho e erra feio em audio curto: numa
    # chamada real de 17 s ele detectou "english" e devolveu "Thank you very much.".
    it 'informa o idioma da conta' do
      account.update!(locale: 'pt_BR')

      described_class.new(blob: attachment.file.blob, account: account, with_segments: true)
                     .tap { |svc| allow(svc).to receive(:fetch_audio_file).and_return(audio_file_path) }
                     .tap { |svc| allow(svc.client).to receive(:audio).and_return(audio_api) }
                     .perform

      expect(audio_api).to have_received(:transcribe) do |parameters:|
        expect(parameters[:language]).to eq('pt')
      end
    end

    # Fixar 0.0 desliga o fallback de temperatura da propria API, que e o mecanismo que quebra os
    # loops de repeticao do whisper: no mesmo audio, 0.0 devolveu 79 trechos (um repetido 66 vezes)
    # contra 29 sem ele.
    it 'nao fixa a temperatura, para a API poder quebrar loops de repeticao' do
      service.perform

      expect(audio_api).to have_received(:transcribe) do |parameters:|
        expect(parameters).not_to have_key(:temperature)
      end
    end

    # Stub direto em vez de InstallationConfig: o cache do GlobalConfig vaza entre exemplos e deixa
    # este teste intermitente conforme a ordem de execucao.
    it 'usa o modelo configurado em CALL_TRANSCRIPTION_MODEL' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('CALL_TRANSCRIPTION_MODEL', anything).and_return('whisper-proprio')

      described_class.new(blob: attachment.file.blob, account: account, with_segments: true)
                     .tap { |s| allow(s).to receive(:fetch_audio_file).and_return(audio_file_path) }
                     .tap { |s| allow(s.client).to receive(:audio).and_return(audio_api) }
                     .perform

      expect(audio_api).to have_received(:transcribe) do |parameters:|
        expect(parameters[:model]).to eq('whisper-proprio')
      end
    end

    # Sem segmentos, o caminho de sempre: texto puro e temperatura fixa, que nos modelos novos
    # ajuda justamente por nao terem esse fallback.
    it 'mantem o comportamento antigo quando nao se pede segmentos' do
      simples = described_class.new(blob: attachment.file.blob, account: account)
      allow(simples).to receive(:fetch_audio_file).and_return(audio_file_path)
      allow(simples.client).to receive(:audio).and_return(audio_api)
      allow(audio_api).to receive(:transcribe).and_return({ 'text' => 'Bom dia.' })

      expect(simples.perform).to eq('Bom dia.')
      expect(audio_api).to have_received(:transcribe) do |parameters:|
        expect(parameters[:temperature]).to eq(0.0)
        expect(parameters).not_to have_key(:response_format)
        expect(parameters).not_to have_key(:language)
      end
    end
  end
end
