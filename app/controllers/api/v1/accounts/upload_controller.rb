class Api::V1::Accounts::UploadController < Api::V1::Accounts::BaseController
  def create
    result = if params[:attachment].present?
               create_from_file
             elsif params[:external_url].present?
               create_from_url
             else
               render_error(I18n.t('errors.upload.missing_input'), :unprocessable_entity)
             end

    render_success(result) if result.is_a?(ActiveStorage::Blob)
  end

  # Remove um arquivo que o próprio usuário enviou e não usa mais (hoje: fundo de conversa).
  #
  # O upload cria um blob solto, sem vínculo com nenhum registro, então não dá para descobrir o
  # dono pelo banco: a prova de posse é a lista no perfil de quem está pedindo. Sem essa
  # checagem, qualquer pessoa poderia apagar anexo de conversa alheia passando o id.
  def destroy
    blob = ActiveStorage::Blob.find_by(id: params[:id])
    return head :not_found if blob.blank?
    return head :forbidden unless meu_envio?(blob.id)

    blob.purge_later
    head :ok
  end

  private

  def meu_envio?(blob_id)
    enviados = Current.user.ui_settings&.dig('chat_background_uploads') || []
    enviados.any? { |envio| envio.is_a?(Hash) && envio['blobId'].to_i == blob_id.to_i }
  end

  def create_from_file
    attachment = params[:attachment]
    create_and_save_blob(attachment.tempfile, attachment.original_filename, attachment.content_type)
  end

  def create_from_url
    SafeFetch.fetch(params[:external_url].to_s) do |result|
      create_and_save_blob(result.tempfile, result.filename, result.content_type)
    end
  rescue SafeFetch::HttpError => e
    render_error(I18n.t('errors.upload.fetch_failed_with_message', message: e.message), :unprocessable_entity)
  rescue SafeFetch::FetchError
    render_error(I18n.t('errors.upload.fetch_failed'), :unprocessable_entity)
  rescue SafeFetch::FileTooLargeError
    render_error(I18n.t('errors.upload.file_too_large'), :unprocessable_entity)
  rescue SafeFetch::UnsupportedContentTypeError
    render_error(I18n.t('errors.upload.unsupported_content_type'), :unprocessable_entity)
  rescue SafeFetch::Error
    render_error(I18n.t('errors.upload.invalid_url'), :unprocessable_entity)
  rescue StandardError
    render_error(I18n.t('errors.upload.unexpected'), :internal_server_error)
  end

  def create_and_save_blob(io, filename, content_type)
    ActiveStorage::Blob.create_and_upload!(
      io: io,
      filename: filename,
      content_type: content_type
    )
  end

  def render_success(file_blob)
    render json: { file_url: url_for(file_blob), blob_id: file_blob.signed_id }
  end

  def render_error(message, status)
    render json: { error: message }, status: status
  end
end
