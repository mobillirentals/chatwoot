# Criar, editar e apagar modelo de mensagem. Até aqui a tela só lia: criar exigia ir ao painel da
# Meta, preencher lá e voltar.
#
# Tudo acontece na Meta — não guardamos modelo no banco, só o espelho que a sincronização traz.
# Por isso cada ação sincroniza ao terminar: sem isso a tela mostraria a lista velha até a
# varredura de 3 em 3 horas, e quem acabou de criar acharia que não funcionou.
module Enterprise::Api::V1::Accounts::Inboxes::MessageTemplateActions
  def create_message_template
    return unless ensure_template_management_supported

    render json: template_service.create(template_params)
  rescue Whatsapp::TemplateManagementService::Error => e
    render_could_not_create_error(e.message)
  end

  # A Meta não deixa trocar nome nem idioma de um modelo que já existe, só o conteúdo. E editar um
  # APROVADO o manda de volta para análise — a tela avisa isso antes.
  def update_message_template
    return unless ensure_template_management_supported

    render json: template_service.update(params[:template_id], template_params)
  rescue Whatsapp::TemplateManagementService::Error => e
    render_could_not_create_error(e.message)
  end

  # Apagar é definitivo, e o nome fica indisponível por 30 dias na Meta.
  def destroy_message_template
    return unless ensure_template_management_supported

    template_service.destroy(params[:name], params[:template_id])
    head :ok
  rescue Whatsapp::TemplateManagementService::Error => e
    render_could_not_create_error(e.message)
  end

  private

  def template_service
    @template_service ||= Whatsapp::TemplateManagementService.new(channel: @inbox.channel)
  end

  def template_params
    # `examples` vem como um mapa de número da variável para o valor, então permitimos a chave
    # inteira em vez de listar índice por índice.
    params.permit(:name, :language, :category, :header, :body, :footer,
                  buttons: [:type, :text, :url], examples: {}).to_h.symbolize_keys.tap do |atributos|
      atributos[:buttons] = Array(atributos[:buttons]).map(&:symbolize_keys)
    end
  end

  # 360dialog não alcança a API de modelos da Cloud, e caixa sem credencial de gestão também não.
  def ensure_template_management_supported
    canal = @inbox.channel
    return true if canal.is_a?(Channel::Whatsapp) && canal.provider == 'whatsapp_cloud'

    render_could_not_create_error(I18n.t('errors.whatsapp.templates.inbox_not_supported'))
    false
  end
end
