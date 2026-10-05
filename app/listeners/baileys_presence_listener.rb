# Leva o "digitando..." do agente até o aparelho do cliente, nas caixas atendidas pela ponte
# Baileys.
#
# O painel já avisa o backend quando o agente escreve (POST toggle_typing_status), e isso vira
# evento de verdade — o mesmo que o widget usa para mostrar "digitando" do outro lado. Aqui ele
# também atravessa para o WhatsApp.
#
# Não existe equivalente na API oficial: a Meta não expõe indicador de digitação. É uma coisa que
# só o caminho não oficial permite.
class BaileysPresenceListener < BaseListener
  def conversation_typing_on(event)
    avisar(event, 'composing')
  end

  def conversation_typing_off(event)
    avisar(event, 'paused')
  end

  private

  def avisar(event, estado)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.blank?
    return unless agente_digitando_para_o_cliente?(event)

    canal = canal_da_ponte(conversation)
    return if canal.blank?

    destino = conversation.contact_inbox&.source_id
    canal.provider_service.avisar_presenca(destino, estado) if destino.present?
  end

  def agente_digitando_para_o_cliente?(event)
    # O cliente digitando no widget também dispara este evento, e mandar 'composing' ao WhatsApp
    # nesse caso diria ao cliente que ELE está digitando.
    return false unless event.data[:user].is_a?(User)

    # Nota privada é conversa interna da equipe: avisar "digitando" ao cliente entregaria que algo
    # está sendo escrito sobre ele, que ele nunca vai ver.
    !ActiveModel::Type::Boolean.new.cast(event.data[:is_private])
  end

  def canal_da_ponte(conversation)
    canal = conversation.inbox.channel
    canal if canal.is_a?(Channel::Whatsapp) && canal.baileys?
  end
end
