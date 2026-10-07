# Recado de voz da chamada: o que o cliente ouve quando a ligação é recusada, em vez de o telefone
# cair na cara dele. Mora inteiro na Meta — aqui só lemos, gravamos e servimos o áudio atual para
# quem quiser conferir o que está no ar.
#
# Separado do controller de caixas porque são três ações de um assunto só; espremê-las lá dentro
# passava o arquivo do limite de tamanho sem deixar nada mais claro.
module Enterprise::Api::V1::Accounts::Inboxes::CallVoicemailActions
  def call_voicemail
    return unless ensure_whatsapp_calling_supported

    render json: voicemail_service.fetch
  rescue Whatsapp::CallVoicemailService::Error => e
    render_could_not_create_error(e.message)
  end

  def set_call_voicemail
    return unless ensure_whatsapp_calling_supported

    return desligar_recado if ActiveModel::Type::Boolean.new.cast(params[:disable])
    return render_could_not_create_error(I18n.t('errors.whatsapp.calls.voicemail_audio_required')) if params[:audio].blank?

    gravar_recado
  rescue Whatsapp::CallVoicemailService::Error => e
    render_could_not_create_error(e.message)
  end

  # O áudio só sai da Meta com o token, que não pode ir ao navegador: servimos os bytes.
  def call_voicemail_announcement
    return unless ensure_whatsapp_calling_supported

    bytes = voicemail_service.announcement_bytes
    return head :no_content if bytes.blank?

    send_data bytes, type: Whatsapp::CallVoicemailService::ANNOUNCEMENT_MIME, disposition: 'inline'
  rescue Whatsapp::CallVoicemailService::Error => e
    render_could_not_create_error(e.message)
  end

  private

  def desligar_recado
    voicemail_service.disable
    render json: voicemail_service.fetch
  end

  def gravar_recado
    voicemail_service.enable(
      io: params[:audio].tempfile,
      filename: params[:audio].original_filename,
      triggers: params[:triggers].to_s.split(','),
      timeout_seconds: params[:timeout_seconds]
    )
    render json: voicemail_service.fetch
  end

  def voicemail_service
    @voicemail_service ||= Whatsapp::CallVoicemailService.new(channel: @inbox.channel)
  end
end
