require 'rails_helper'

RSpec.describe Voice::CallTranscriptionService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:channel) { create(:channel_twilio_sms, :with_voice, account: account, phone_number: '+15551238888') }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content_type: :voice_call) }
  let(:call) do
    create(:call, account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, status: 'completed', message: message)
  end

  before do
    allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
    call.recording.attach(
      io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
      filename: 'call-recording.mp3',
      content_type: 'audio/mpeg'
    )
  end

  describe '#perform' do
    it 'stores the transcript on the call' do
      allow(Llm::SpeechToTextService).to receive(:new).and_return(
        instance_double(Llm::SpeechToTextService, perform: 'Hello, how can I help?')
      )

      described_class.new(call: call).perform

      expect(call.reload.transcript).to eq('Hello, how can I help?')
    end

    it 'skips calls whose inbox has transcription turned off' do
      channel.update!(provider_config: channel.provider_config.merge('transcription_enabled' => false))

      expect(Llm::SpeechToTextService).not_to receive(:new)

      described_class.new(call: call).perform

      expect(call.reload.transcript).to be_nil
    end

    it 'skips calls that are already transcribed' do
      call.update!(transcript: 'Existing transcript')

      expect(Llm::SpeechToTextService).not_to receive(:new)

      described_class.new(call: call).perform
    end

    it 'skips calls without a recording' do
      call.recording.purge

      expect(Llm::SpeechToTextService).not_to receive(:new)

      described_class.new(call: call).perform
    end

    it 'skips when transcription is unavailable for the account' do
      allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(false)

      expect(Llm::SpeechToTextService).not_to receive(:new)

      described_class.new(call: call).perform
    end

    it 'leaves the transcript blank when nothing comes back' do
      allow(Llm::SpeechToTextService).to receive(:new).and_return(
        instance_double(Llm::SpeechToTextService, perform: '')
      )

      described_class.new(call: call).perform

      expect(call.reload.transcript).to be_nil
    end

    # A chamada do WhatsApp e gravada no navegador do atendente e sobe como anexo de audio da
    # mensagem; `call.recording` fica vazio. Sem enxergar esse anexo, a transcricao so existia nas
    # chamadas do Twilio.
    describe 'gravacao que veio como anexo da mensagem (WhatsApp)' do
      before do
        call.recording.purge
        message.attachments.create!(
          account_id: account.id, file_type: :audio,
          file: Rack::Test::UploadedFile.new(Rails.public_path.join('audio/widget/ding.mp3'), 'audio/mpeg')
        )
      end

      it 'transcreve a partir do anexo' do
        allow(Llm::SpeechToTextService).to receive(:new).and_return(
          instance_double(Llm::SpeechToTextService, perform: 'Alo, pode falar?')
        )

        described_class.new(call: call).perform

        expect(call.reload.transcript).to eq('Alo, pode falar?')
      end

      # O anexo ja foi transcrito pelo seu proprio callback; chamar o Whisper de novo seria pagar
      # duas vezes pelo mesmo audio.
      it 'reaproveita o texto ja transcrito do anexo, sem chamar o motor de novo' do
        anexo = message.attachments.first
        anexo.update!(meta: { transcribed_text: 'Bom dia, e sobre a minha parcela.' })

        expect(Llm::SpeechToTextService).not_to receive(:new)

        described_class.new(call: call).perform

        expect(call.reload.transcript).to eq('Bom dia, e sobre a minha parcela.')
      end

      it 'ainda respeita a transcricao desligada na caixa' do
        channel.update!(provider_config: channel.provider_config.merge('transcription_enabled' => false))

        expect(Llm::SpeechToTextService).not_to receive(:new)

        described_class.new(call: call).perform

        expect(call.reload.transcript).to be_nil
      end
    end

    it 'reindexes before broadcasting so a retry after a reindex failure does not resend the update event' do
      call.update!(transcript: 'Existing transcript')
      allow(ChatwootApp).to receive(:advanced_search_allowed?).and_return(true)
      allow(message).to receive(:reindex).and_raise(StandardError, 'reindex boom')

      expect(message).not_to receive(:send_update_event)
      expect { described_class.new(call: call).perform }.to raise_error(StandardError, 'reindex boom')
    end
  end
end
