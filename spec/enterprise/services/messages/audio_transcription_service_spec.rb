require 'rails_helper'

RSpec.describe Messages::AudioTranscriptionService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }

  before do
    # Create required installation configs
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_API_KEY') { |config| config.value = 'test-api-key' }
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_MODEL') { |config| config.value = 'gpt-4o-mini' }

    # Mock usage limits for transcription to be available
    allow(account).to receive(:usage_limits).and_return(
      {
        agents: ChatwootApp.max_limit,
        inboxes: ChatwootApp.max_limit,
        captain: { responses: { current_available: 100 } }
      }
    )
  end

  describe '#perform' do
    let(:service) { described_class.new(attachment) }

    context 'when captain_integration feature is not enabled' do
      before do
        account.disable_features!('captain_integration')
      end

      it 'returns transcription limit exceeded' do
        expect(service.perform).to eq({ error: 'Transcription limit exceeded' })
      end
    end

    context 'when the message is a call recording on an inbox with transcription turned off' do
      let(:channel) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      end
      let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
      let(:message) { create(:message, account: account, conversation: conversation, inbox: channel.inbox, content_type: 'voice_call') }

      before do
        channel.update!(provider_config: channel.provider_config.merge('transcription_enabled' => false))
        allow(Llm::SpeechToTextService).to receive(:new)
      end

      it 'skips transcription' do
        expect(service.perform).to eq({ error: 'Transcription disabled for this inbox' })
        expect(Llm::SpeechToTextService).not_to have_received(:new)
      end

      # The setting is about call recordings; an ordinary voice note on the same inbox is untouched.
      it 'still transcribes a voice note sent by the contact' do
        message.update!(content_type: 'text')

        expect(service.perform).not_to eq({ error: 'Transcription disabled for this inbox' })
      end
    end

    context 'when transcription is successful' do
      before do
        allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
        allow(service).to receive(:transcribe_audio).and_return('Hello world transcription')
      end

      it 'returns successful transcription' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Hello world transcription' })
      end
    end

    context 'when audio transcriptions are disabled' do
      before do
        account.update!(audio_transcriptions: false)
      end

      it 'returns error for transcription limit exceeded' do
        result = service.perform
        expect(result).to eq({ error: 'Transcription limit exceeded' })
      end
    end

    context 'when attachment already has transcribed text' do
      before do
        attachment.update!(meta: { transcribed_text: 'Existing transcription' })
        allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
      end

      it 'returns existing transcription without calling API' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Existing transcription' })
      end
    end

    context 'when the audio exceeds the transcription byte limit' do
      before do
        attachment.file.attach(
          io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
          filename: 'large.mp3',
          content_type: 'audio/mpeg'
        )
        allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
        allow(attachment.file.blob).to receive(:byte_size).and_return(Llm::SpeechToTextService::BYTE_LIMIT + 1)
      end

      it 'returns an error without transcribing' do
        expect(service).not_to receive(:transcribe_audio)
        expect(service.perform).to eq({ error: 'Audio too large for transcription' })
      end
    end

    # A gravacao de uma chamada chega aqui como anexo de audio como qualquer outro, e ja era
    # transcrita — o texto so nunca chegava em `call.transcript`, que e o campo que a tela da
    # chamada mostra.
    describe 'gravacao de chamada' do
      # Mensagem de chamada so existe em caixa de voz; a do spec, por padrao, e um widget.
      let(:channel) do
        create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                                  validate_provider_config: false, sync_templates: false)
      end
      let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
      let(:message) { create(:message, account: account, conversation: conversation, content_type: :voice_call) }
      let!(:call) do
        create(:call, account: account, inbox: conversation.inbox, conversation: conversation,
                      contact: conversation.contact, status: 'completed', message: message)
      end

      # `require sidekiq/testing` no rails_helper troca o adapter do ActiveJob, e os matchers de job
      # exigem o :test. Restaurado no fim para nao vazar para os outros exemplos do arquivo.
      around do |exemplo|
        adapter = ActiveJob::Base.queue_adapter
        ActiveJob::Base.queue_adapter = :test
        exemplo.run
        ActiveJob::Base.queue_adapter = adapter
      end

      before do
        attachment.file.attach(
          io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
          filename: 'call-recording.mp3', content_type: 'audio/mpeg'
        )
        allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
        allow(Llm::SpeechToTextService).to receive(:new).and_return(
          instance_double(Llm::SpeechToTextService, perform: 'Alo, e sobre a minha parcela.')
        )
      end

      it 'enfileira o job que leva o texto para a chamada' do
        expect { service.perform }.to have_enqueued_job(Voice::CallTranscriptionJob).with(call.id)
      end

      it 'nao enfileira nada para um audio comum de cliente' do
        message.update!(content_type: :text)

        expect { service.perform }.not_to have_enqueued_job(Voice::CallTranscriptionJob)
      end
    end
  end
end
