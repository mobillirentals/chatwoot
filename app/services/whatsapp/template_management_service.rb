# Criar, editar e apagar modelo de mensagem na Meta.
#
# O upstream já criava modelo pela API, mas só o do CSAT, com forma fixa (Whatsapp::CsatTemplateService).
# Aqui a forma vem de fora, então as regras da Meta precisam estar explícitas: ela recusa o modelo
# inteiro por detalhe de formato, e a mensagem de erro costuma ser genérica demais para o usuário
# entender o que fazer.
class Whatsapp::TemplateManagementService
  CATEGORIES = %w[MARKETING UTILITY].freeze
  # AUTHENTICATION fica de fora de propósito: a Meta impõe formato próprio e regras de segurança
  # nessa categoria, e criar errado ali trava o envio de código de acesso.

  BUTTON_TYPES = %w[QUICK_REPLY URL].freeze
  LIMITS = { name: 512, header: 60, body: 1024, footer: 60, buttons: 10 }.freeze
  NAME_FORMAT = /\A[a-z0-9_]+\z/

  class Error < StandardError; end

  pattr_initialize [:channel!]

  def create(atributos)
    corpo = montar(atributos).merge(name: atributos[:name].to_s, language: atributos[:language].to_s)
    validar_nome!(corpo[:name])

    resposta = post("#{waba_path}/message_templates", corpo)
    sincronizar
    { id: resposta['id'], status: resposta['status'] || 'PENDING', category: resposta['category'] }
  end

  # A Meta não deixa trocar nome nem idioma de um modelo existente, e nem a categoria de um que já
  # está aprovado — por isso a categoria só vai no corpo quando quem chamou pediu de propósito.
  # Um modelo aprovado é reaprovado automaticamente depois da edição, a menos que reprove na
  # análise; o limite é de 1 edição a cada 24 h e 10 a cada 30 dias.
  def update(template_id, atributos)
    post(template_id.to_s, montar(atributos, categoria_obrigatoria: false))
    sincronizar
    { id: template_id }
  end

  def destroy(name, template_id = nil)
    caminho = "#{waba_path}/message_templates?name=#{CGI.escape(name.to_s)}"
    caminho += "&hsm_id=#{template_id}" if template_id.present?

    resposta = HTTParty.delete("#{graph}/#{caminho}", headers: headers)
    raise Error, mensagem_de_erro(resposta) unless resposta.success?

    sincronizar
    true
  end

  private

  def montar(atributos, categoria_obrigatoria: true)
    # Os exemplos chegam indexados pelo número da variável e são lidos lá em `com_exemplo`.
    @exemplos = (atributos[:examples] || {}).transform_keys(&:to_s)
    corpo = { components: componentes(atributos).compact }
    return corpo if !categoria_obrigatoria && atributos[:category].blank?

    categoria = atributos[:category].to_s.upcase
    raise Error, I18n.t('errors.whatsapp.templates.category_not_supported') unless categoria.in?(CATEGORIES)

    corpo.merge(category: categoria)
  end

  def componentes(atributos)
    [
      cabecalho(atributos[:header]),
      corpo(atributos[:body]),
      rodape(atributos[:footer]),
      botoes(atributos[:buttons])
    ]
  end

  def cabecalho(texto)
    return if texto.blank?

    exigir_tamanho!(texto, :header)
    com_exemplo({ type: 'HEADER', format: 'TEXT', text: texto }, texto, :header_text)
  end

  def corpo(texto)
    raise Error, I18n.t('errors.whatsapp.templates.body_required') if texto.blank?

    exigir_tamanho!(texto, :body)
    recusar_variavel_pendurada!(texto)
    com_exemplo({ type: 'BODY', text: texto }, texto, :body_text)
  end

  # A Meta chama de "dangling parameter": o corpo não pode começar nem terminar com variável.
  def recusar_variavel_pendurada!(texto)
    limpo = texto.to_s.strip
    return unless limpo.match?(/\A\{\{\d+\}\}/) || limpo.match?(/\{\{\d+\}\}\z/)

    raise Error, I18n.t('errors.whatsapp.templates.dangling_variable')
  end

  # Rodapé não aceita variável — a Meta recusa sem dizer onde está o problema.
  def rodape(texto)
    return if texto.blank?

    raise Error, I18n.t('errors.whatsapp.templates.footer_no_variables') if variaveis(texto).any?

    exigir_tamanho!(texto, :footer)
    { type: 'FOOTER', text: texto }
  end

  def botoes(lista)
    lista = Array(lista).reject { |b| b[:text].blank? }
    return if lista.empty?

    raise Error, I18n.t('errors.whatsapp.templates.too_many_buttons', max: LIMITS[:buttons]) if lista.size > LIMITS[:buttons]

    { type: 'BUTTONS', buttons: lista.map { |botao| montar_botao(botao) } }
  end

  def montar_botao(botao)
    tipo = botao[:type].to_s.upcase
    raise Error, I18n.t('errors.whatsapp.templates.button_not_supported') unless tipo.in?(BUTTON_TYPES)
    return { type: 'QUICK_REPLY', text: botao[:text] } if tipo == 'QUICK_REPLY'

    raise Error, I18n.t('errors.whatsapp.templates.button_url_required') if botao[:url].blank?

    { type: 'URL', text: botao[:text], url: botao[:url] }
  end

  # Texto com variável exige exemplo, senão a Meta recusa. O exemplo é o que o analista da Meta lê
  # para entender o modelo, então vem de quem escreveu; o genérico é só a rede de segurança.
  def com_exemplo(componente, texto, chave)
    encontradas = variaveis(texto)
    return componente if encontradas.empty?

    exemplos = encontradas.map { |n| @exemplos[n.to_s].presence || "exemplo #{n}" }
    componente.merge(example: { chave => chave == :header_text ? exemplos : [exemplos] })
  end

  def variaveis(texto)
    texto.to_s.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).uniq.sort
  end

  def exigir_tamanho!(texto, campo)
    return if texto.to_s.length <= LIMITS[campo]

    raise Error, I18n.t('errors.whatsapp.templates.too_long', field: campo, max: LIMITS[campo])
  end

  def validar_nome!(nome)
    raise Error, I18n.t('errors.whatsapp.templates.name_format') unless nome.match?(NAME_FORMAT)

    exigir_tamanho!(nome, :name)
  end

  def post(caminho, corpo)
    resposta = HTTParty.post("#{graph}/#{caminho}", headers: headers.merge('Content-Type' => 'application/json'),
                                                    body: corpo.to_json)
    raise Error, mensagem_de_erro(resposta) unless resposta.success?

    resposta.parsed_response.is_a?(Hash) ? resposta.parsed_response : {}
  end

  # Sem isto a tela continuaria mostrando a lista antiga até a varredura de 3 em 3 horas.
  def sincronizar
    channel.provider_service.sync_templates
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP] sincronização após mexer em modelo falhou: #{e.message}")
  end

  def graph
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')}"
  end

  def waba_path
    channel.provider_config['business_account_id']
  end

  def headers
    { 'Authorization' => "Bearer #{channel.template_access_token}" }
  end

  def mensagem_de_erro(resposta)
    erro = begin
      JSON.parse(resposta.body.to_s)['error'] || {}
    rescue JSON::ParserError
      {}
    end
    erro['error_user_msg'].presence || erro['message'].presence || "Meta respondeu #{resposta.code}"
  end
end
