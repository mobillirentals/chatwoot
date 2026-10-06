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

    transcript = Llm::SpeechToTextService.new(blob: recording_blob, account: call.account).perform
    call.update!(transcript: transcript) if transcript.present?
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
    call.message&.attachments&.find_by(file_type: :audio)&.file&.blob
  end
end
