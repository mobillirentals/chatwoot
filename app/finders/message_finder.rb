class MessageFinder
  # quantos resultados o filtro devolve por vez (a tela pede mais conforme o usuario rola)
  RESULTADOS_POR_VEZ = 50

  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    lista = if @params[:filter_internal_messages].blank?
              conversation_messages
            else
              conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
            end
    aplica_filtros(lista)
  end

  # Filtro dentro da conversa (texto e periodo). Conversa de historico chega a milhares de
  # mensagens: rolar ate 2023 para achar um assunto nao e opcao. A consulta usa o indice de
  # conversation_id e filtra so o que pertence a ela, entao sai em milissegundos.
  def aplica_filtros(lista)
    lista = lista.where('messages.content ILIKE ?', "%#{sanitiza(@params[:q])}%") if @params[:q].present?
    lista = lista.where('messages.created_at >= ?', Time.zone.parse(@params[:since].to_s)) if data?(@params[:since])
    lista = lista.where('messages.created_at <= ?', fim_do_dia(@params[:until])) if data?(@params[:until])
    lista
  end

  def filtrando?
    @params[:q].present? || data?(@params[:since]) || data?(@params[:until])
  end

  def data?(valor)
    valor.present? && Time.zone.parse(valor.to_s).present?
  rescue ArgumentError
    false
  end

  # "ate 31/12" tem que incluir o dia 31 inteiro, senao o usuario procura no ultimo dia e nao acha
  def fim_do_dia(valor)
    Time.zone.parse(valor.to_s).end_of_day
  end

  def sanitiza(texto)
    ActiveRecord::Base.sanitize_sql_like(texto.to_s.strip)
  end

  def current_messages
    # com filtro ativo a tela mostra uma lista de resultados, nao a janela deslizante da conversa:
    # os 20 ultimos nao servem de nada quando se procura algo de 2023
    return resultados_do_filtro if filtrando?

    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    messages.reorder('created_at asc').where('id > ?', after_id).limit(100)
  end

  def messages_before(before_id)
    messages.reorder('created_at desc').where('id < ?', before_id).limit(20).reverse
  end

  def messages_between(after_id, before_id)
    messages.reorder('created_at asc').where('id >= ? AND id < ?', after_id, before_id).limit(1000)
  end

  def messages_latest
    messages.reorder('created_at desc').limit(20).reverse
  end

  def resultados_do_filtro
    lista = messages.reorder('created_at desc')
    lista = lista.where('messages.id < ?', @params[:before].to_i) if @params[:before].present?
    lista.limit(RESULTADOS_POR_VEZ).reverse
  end
end

MessageFinder.prepend_mod_with('MessageFinder')
