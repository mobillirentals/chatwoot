# Devolve o visto-azul ao cliente nas caixas da ponte Baileys.
#
# Em job, e nao no request: abrir uma conversa no painel nao pode esperar uma chamada HTTP a
# ponte, e visto-azul e cortesia — se falhar, o agente nem fica sabendo, que e o certo aqui.
class Whatsapp::MarkAsReadJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    channel = conversation.inbox.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.baileys?

    destino = conversation.contact_inbox&.source_id
    return if destino.blank?

    channel.provider_service.marcar_como_lida(destino)
  end
end
