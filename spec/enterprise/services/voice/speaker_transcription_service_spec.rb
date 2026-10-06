require 'rails_helper'

# Saber quem falou cada frase não vem do modelo de transcrição: vem de ter os dois lados gravados
# separados, transcritos separados e intercalados pelo tempo.
RSpec.describe Voice::SpeakerTranscriptionService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agente) { create(:user, account: account, name: 'Marina') }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, content_type: :voice_call)
  end
  let(:call) do
    create(:call, account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                  provider: :whatsapp, status: 'completed', message: message, accepted_by_agent: agente)
  end

  def anexar_lados
    %i[recording_agent recording_contact].each do |lado|
      call.public_send(lado).attach(
        io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
        filename: "#{lado}.mp3", content_type: 'audio/mpeg'
      )
    end
  end

  # O serviço chama o motor uma vez por lado; o dublê responde conforme a ordem das chamadas.
  def responder_com(*respostas)
    dubles = respostas.map { |r| instance_double(Llm::SpeechToTextService, perform: r) }
    allow(Llm::SpeechToTextService).to receive(:new).and_return(*dubles)
  end

  before do
    allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
    allow(Llm::SpeechToTextService).to receive(:too_large?).and_return(false)
    anexar_lados
  end

  describe '#perform' do
    it 'intercala os dois lados pelo tempo e marca quem falou' do
      responder_com(
        { 'segments' => [{ 'start' => 2.0, 'end' => 3.0, 'text' => ' Pois não?' }] },
        { 'segments' => [{ 'start' => 0.0, 'end' => 1.5, 'text' => ' Bom dia.' },
                         { 'start' => 4.0, 'end' => 5.0, 'text' => ' É sobre a parcela.' }] }
      )

      described_class.new(call: call).perform

      expect(call.reload.transcript_segments).to eq(
        [
          { 'speaker' => 'contact', 'start' => 0.0, 'end' => 1.5, 'text' => 'Bom dia.' },
          { 'speaker' => 'agent', 'start' => 2.0, 'end' => 3.0, 'text' => 'Pois não?' },
          { 'speaker' => 'contact', 'start' => 4.0, 'end' => 5.0, 'text' => 'É sobre a parcela.' }
        ]
      )
    end

    # O campo plano continua existindo para quem não sabe de locutor: busca, Captain, telas antigas.
    it 'monta o texto corrido com os nomes de cada lado' do
      responder_com(
        { 'segments' => [{ 'start' => 1.0, 'end' => 2.0, 'text' => 'Pois não?' }] },
        { 'segments' => [{ 'start' => 0.0, 'end' => 0.5, 'text' => 'Bom dia.' }] }
      )

      described_class.new(call: call).perform

      expect(call.reload.transcript)
        .to eq("#{conversation.contact.name}: Bom dia.\n#{agente.available_name}: Pois não?")
    end

    # O whisper entra em loop no silêncio do fim e repete a última frase até o arquivo acabar —
    # num teste real, 66 cópias de "E aí?".
    it 'corta a repetição em loop do fim da gravação' do
      eco = Array.new(8) { |i| { 'start' => 10.0 + i, 'end' => 11.0 + i, 'text' => 'E aí?' } }
      responder_com(
        { 'segments' => [{ 'start' => 0.0, 'end' => 1.0, 'text' => 'Alô.' }] + eco },
        { 'segments' => [] }
      )

      described_class.new(call: call).perform

      textos = call.reload.transcript_segments.map { |s| s['text'] }
      expect(textos).to eq(['Alô.', 'E aí?', 'E aí?'])
    end

    # Os lados são insumo de transcrição, não de reprodução — o player toca a mistura. Guardados,
    # triplicariam o armazenamento de cada chamada sem nunca mais serem lidos.
    it 'descarta as gravações dos lados quando termina' do
      responder_com({ 'segments' => [{ 'start' => 0.0, 'end' => 1.0, 'text' => 'Oi.' }] }, { 'segments' => [] })

      perform_enqueued_jobs { described_class.new(call: call).perform }

      call.reload
      expect(call.recording_agent).not_to be_attached
      expect(call.recording_contact).not_to be_attached
    end

    it 'não faz nada quando só um lado chegou' do
      call.recording_contact.purge

      expect(Llm::SpeechToTextService).not_to receive(:new)

      described_class.new(call: call).perform

      expect(call.reload.transcript_segments).to be_empty
    end

    it 'não refaz o trabalho de uma chamada já transcrita' do
      call.update!(transcript_segments: [{ 'speaker' => 'agent', 'start' => 0, 'end' => 1, 'text' => 'Oi.' }])

      expect(Llm::SpeechToTextService).not_to receive(:new)

      described_class.new(call: call).perform
    end

    it 'respeita a transcrição desligada na caixa' do
      channel.update!(provider_config: channel.provider_config.merge('transcription_enabled' => false))

      expect(Llm::SpeechToTextService).not_to receive(:new)

      described_class.new(call: call).perform

      expect(call.reload.transcript_segments).to be_empty
    end

    # Um lado que o modelo recusa não pode levar o outro junto.
    it 'aproveita o lado que respondeu quando o outro falha' do
      bom = instance_double(Llm::SpeechToTextService,
                            perform: { 'segments' => [{ 'start' => 0.0, 'end' => 1.0, 'text' => 'Bom dia.' }] })
      ruim = instance_double(Llm::SpeechToTextService)
      allow(ruim).to receive(:perform).and_raise(Faraday::BadRequestError.new('audio ruim'))
      allow(Llm::SpeechToTextService).to receive(:new).and_return(ruim, bom)

      described_class.new(call: call).perform

      expect(call.reload.transcript_segments.map { |s| s['speaker'] }).to eq(['contact'])
    end

    it 'deixa a chamada como estava quando nenhum lado rende texto' do
      responder_com({ 'segments' => [] }, { 'segments' => [] })

      described_class.new(call: call).perform

      expect(call.reload.transcript_segments).to be_empty
      expect(call.recording_agent).to be_attached
    end
  end
end
