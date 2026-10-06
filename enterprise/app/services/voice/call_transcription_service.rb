class Voice::CallTranscriptionService
  pattr_initialize [:call!]

  def perform
    # Split so a publish failure can retry without re-running (and re-charging) transcription.
    transcribe if call.transcript.blank?
    publish(call.message) if call.transcript.present?
  end

  private

  def transcribe
    return if recording_blob.blank?
    return unless call.inbox.channel.transcription_enabled?
    return unless Llm::SpeechToTextService.available_for?(call.account)
    return if Llm::SpeechToTextService.too_large?(recording_blob)

    transcript = transcribed_text
    call.update!(transcript: transcript) if transcript.present?
  end

  # A gravacao que sobe como anexo ja foi transcrita pelo `after_create_commit` do Attachment, e o
  # texto fica em `meta['transcribed_text']`. Reaproveitar e o que impede pagar o Whisper duas vezes
  # pelo mesmo audio — `Messages::AudioTranscriptionService` devolve o que ja existe e so chama a
  # API quando ainda nao ha nada. O Twilio nao tem anexo: cai no caminho de sempre.
  def transcribed_text
    return Llm::SpeechToTextService.new(blob: recording_blob, account: call.account).perform if recording_attachment.blank?

    Messages::AudioTranscriptionService.new(recording_attachment).perform[:transcriptions]
  end

  def publish(message)
    return if message.blank?

    # Reindex before broadcasting: if reindexing fails and the job retries,
    # the transcript is already present so only publish reruns. Sending the
    # update event first would resend it to clients on every such retry.
    message.reindex if ChatwootApp.advanced_search_allowed?

    # Rebroadcast the message so connected clients pick up the embedded Call
    # payload (now with transcript) without a refetch.
    message.reload.send_update_event
  end

  # O Twilio guarda a gravacao em `call.recording`. A chamada do WhatsApp e gravada no navegador do
  # atendente e sobe como anexo de audio da mensagem (e de la que o player da conversa toca), entao
  # `call.recording` fica vazio e a transcricao sumia justamente nessas chamadas.
  def recording_blob
    return @recording_blob if defined?(@recording_blob)

    @recording_blob = call.recording.attached? ? call.recording.blob : message_recording_blob
  end

  def message_recording_blob
    recording_attachment&.file&.blob
  end

  def recording_attachment
    return @recording_attachment if defined?(@recording_attachment)
    return @recording_attachment = nil if call.recording.attached?

    @recording_attachment = call.message&.attachments&.find_by(file_type: :audio)
  end
end
