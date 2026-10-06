class Messages::AudioTranscriptionService
  attr_reader :attachment, :message, :account

  def initialize(attachment)
    @attachment = attachment
    @message = attachment.message
    @account = message&.account
  end

  def perform
    return { error: 'Message not found' } if message.blank?
    return { error: 'Transcription disabled for this inbox' } if call_recording_transcription_disabled?
    return { error: 'Transcription limit exceeded' } unless Llm::SpeechToTextService.available_for?(account)
    return { error: 'Audio too large for transcription' } if Llm::SpeechToTextService.too_large?(attachment.file&.blob)

    transcriptions = transcribe_audio
    Rails.logger.info "Audio transcription successful: #{transcriptions}"
    { success: true, transcriptions: transcriptions }
  rescue Faraday::UnauthorizedError
    Rails.logger.warn('Skipping audio transcription: OpenAI configuration is invalid or disabled (401 Unauthorized).')
    { error: 'OpenAI configuration is invalid or disabled (401)' }
  end

  private

  # Call recordings honour the inbox's "Transcribe recordings" setting; ordinary voice notes don't.
  def call_recording_transcription_disabled?
    return false unless message.voice_call?
    return true unless message.inbox.channel.transcription_enabled?

    # Com os dois lados gravados, quem transcreve e o fluxo por locutor. Transcrever a mistura
    # tambem seria pagar de novo por um texto que nao sabe quem falou. Sem os dois lados (envio
    # falhou, chamada antiga), este caminho segue valendo: a degradacao e automatica.
    message.call&.sides_recorded? || false
  end

  def transcribe_audio
    transcribed_text = attachment.meta&.[]('transcribed_text') || ''
    return transcribed_text if transcribed_text.present?

    transcribed_text = Llm::SpeechToTextService.new(blob: attachment.file.blob, account: account).perform
    update_transcription(transcribed_text)
    transcribed_text
  end

  def update_transcription(transcribed_text)
    return if transcribed_text.blank?

    attachment.update!(meta: { transcribed_text: transcribed_text })
    message.reload.send_update_event
    copy_to_call

    return unless ChatwootApp.advanced_search_allowed?

    message.reindex
  end

  # A gravacao de uma chamada do WhatsApp chega aqui como anexo de audio como qualquer outro, e ja
  # era transcrita — o texto so nunca chegava em `call.transcript`, que e o campo que a tela da
  # chamada mostra. Enfileirar daqui garante a ordem: quando o job da chamada roda, o texto ja
  # existe no anexo e ele so copia, sem transcrever de novo.
  def copy_to_call
    return unless message.voice_call?
    return if message.call.blank?

    Voice::CallTranscriptionJob.perform_later(message.call.id)
  end
end
