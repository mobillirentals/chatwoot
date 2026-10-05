# WhatsApp pela ponte Baileys (protocolo do WhatsApp Web), para número que não está na API
# oficial. O BaseService documenta este ponto de extensão: herdar e implementar o envio.
#
# Diferente dos outros dois provedores, aqui não se fala com a Meta: a ponte é um serviço Node
# nosso que mantém a sessão pareada por QR code e faz o trabalho de protocolo. Este provider só
# conversa com ela por HTTP.
#
# ⚠️ Baileys é engenharia reversa do WhatsApp Web e contraria os termos da Meta — o número pode
# ser banido, sem recurso. Use em número secundário, nunca no principal da operação.
#
# provider_config esperado:
#   bridge_url   — onde a ponte responde (ex.: http://whatsapp-baileys:3400)
#   bridge_token — segredo exigido pela ponte no header X-Bridge-Token
#   webhook_verify_token — segredo que a ponte apresenta ao entregar mensagem recebida
class Whatsapp::Providers::WhatsappBaileysService < Whatsapp::Providers::BaseService
  # A ponte é local; se ela não respondeu nesse tempo, não vai responder.
  TIMEOUT_SEGUNDOS = 15

  # A ponte atende varios numeros, um por sessao, e a sessao e o proprio numero da caixa -- entao
  # nao ha id separado para guardar no provider_config.
  def sessao_url(caminho)
    "#{bridge_url}/sessions/#{id_da_sessao}/#{caminho}"
  end

  def id_da_sessao
    whatsapp_channel.phone_number.to_s.gsub(/\D/, '')
  end

  # Devolve o visto-azul ao cliente. Chamado quando o agente abre a conversa no painel.
  def marcar_como_lida(numero_do_cliente)
    HTTParty.post(sessao_url('read'), headers: api_headers, body: { to: numero_do_cliente }.to_json,
                                      timeout: TIMEOUT_SEGUNDOS)
  rescue StandardError => e
    # Visto-azul e cortesia: falhar aqui nao pode atrapalhar o agente abrindo a conversa.
    Rails.logger.warn "[BAILEYS] falha ao marcar como lida: #{e.message}"
    nil
  end

  # 'composing' vira "digitando..." no aparelho do cliente; 'paused' apaga.
  def avisar_presenca(numero_do_cliente, estado)
    HTTParty.post(sessao_url('presence'), headers: api_headers,
                                          body: { to: numero_do_cliente, state: estado }.to_json,
                                          timeout: TIMEOUT_SEGUNDOS)
  rescue StandardError => e
    Rails.logger.warn "[BAILEYS] falha ao avisar presenca: #{e.message}"
    nil
  end

  def send_message(phone_number, message)
    # Anexo fica para a rodada seguinte. Falhar explicitamente é melhor que mandar só o texto e
    # deixar o agente achar que a imagem foi entregue.
    return anexo_ainda_nao_suportado(message) if message.attachments.present?

    enviar_texto(phone_number, message)
  end

  # Template é mecanismo da API oficial: a Meta aprova o texto e ele vale fora da janela de 24h.
  # Pela ponte não existe nem aprovação nem janela, então um "template" aqui seria só texto comum
  # — e aceitar silenciosamente daria a entender que a caixa tem templates, que não tem.
  def send_template(_phone_number, _template_info, message)
    registrar_falha(message, I18n.t('errors.whatsapp.baileys.template_unsupported'))
    nil
  end

  # Sem catálogo de templates para sincronizar. Marcar como atualizado evita que o
  # `after_create :sync_templates` do canal fique tentando a cada chamada.
  def sync_templates
    whatsapp_channel.mark_message_templates_updated
    true
  end

  # Roda na validação do canal, então é o que impede salvar uma caixa apontando para uma ponte
  # que não existe ou cujo número não está pareado.
  def validate_provider_config?
    return false if bridge_url.blank?

    resposta = HTTParty.get(sessao_url('health'), headers: api_headers, timeout: TIMEOUT_SEGUNDOS)
    return false unless resposta.success?

    numero_pareado_confere?(resposta.parsed_response)
  rescue StandardError => e
    Rails.logger.error "[BAILEYS] ponte inacessível em #{bridge_url}: #{e.message}"
    false
  end

  def api_headers
    { 'X-Bridge-Token' => whatsapp_channel.provider_config['bridge_token'].to_s, 'Content-Type' => 'application/json' }
  end

  def media_url(media_id)
    sessao_url("media/#{media_id}")
  end

  def error_message(response)
    response.parsed_response&.dig('error').presence || "ponte respondeu #{response.code}"
  rescue StandardError
    "ponte respondeu #{response.code}"
  end

  private

  def enviar_texto(phone_number, message)
    corpo = { to: phone_number, text: message.outgoing_content }
    # Resposta citada: o painel já grava qual mensagem está sendo respondida, e a ponte sabe citar
    # — é o mesmo campo que o provider da API oficial usa.
    citado = message.content_attributes[:in_reply_to_external_id]
    corpo[:quoted_id] = citado if citado.present?

    resposta = HTTParty.post(
      sessao_url('send'),
      headers: api_headers,
      body: corpo.to_json,
      timeout: TIMEOUT_SEGUNDOS
    )

    processar_resposta(resposta, message)
  rescue StandardError => e
    # Ponte fora do ar não pode derrubar o envio em silêncio: a mensagem fica como falhada, que é
    # o que o painel mostra ao agente.
    Rails.logger.error "[BAILEYS] falha ao enviar pela ponte: #{e.message}"
    registrar_falha(message, I18n.t('errors.whatsapp.baileys.bridge_unreachable'))
    nil
  end

  # O `process_response` do BaseService espera o envelope da Meta (`messages[0].id`); a ponte
  # devolve o id direto, então a leitura é própria.
  def processar_resposta(resposta, message)
    if resposta.success? && resposta.parsed_response['error'].blank?
      resposta.parsed_response['message_id'].presence
    else
      handle_error(resposta, message)
      nil
    end
  end

  def anexo_ainda_nao_suportado(message)
    registrar_falha(message, I18n.t('errors.whatsapp.baileys.attachment_unsupported'))
    nil
  end

  def registrar_falha(message, texto)
    return if message.blank?

    message.external_error = texto
    message.status = :failed
    message.save!
  end

  # Pareamento errado é o engano mais fácil de cometer com duas pontes no ar (a de verificação de
  # número e esta), e manda mensagem do número errado sem avisar ninguém.
  def numero_pareado_confere?(saude)
    return false unless saude['whatsapp_connection'] == 'connected'

    pareado = saude['whatsapp_number'].to_s.gsub(/\D/, '')
    esperado = whatsapp_channel.phone_number.to_s.gsub(/\D/, '')
    return true if pareado == esperado

    Rails.logger.error "[BAILEYS] a ponte está pareada com #{pareado}, mas a caixa é #{esperado}"
    false
  end

  def bridge_url
    whatsapp_channel.provider_config['bridge_url'].to_s.chomp('/')
  end
end
