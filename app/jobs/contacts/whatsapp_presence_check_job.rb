# Checagem consultiva de "esse numero tem WhatsApp?" pra um contato recem-criado manualmente
# (ver pontos de disparo em app/controllers/api/v1/accounts/contacts_controller.rb#create e
# .../conversations_controller.rb#create). Nunca re-tenta agressivamente nem derruba o job em
# caso de falha — servico fora do ar so significa "sem selo" no contato, nada quebra por causa
# disso.
class Contacts::WhatsappPresenceCheckJob < ApplicationJob
  queue_as :low

  def perform(contact_id)
    contact = Contact.find_by(id: contact_id)
    return if contact.blank? || contact.phone_number.blank?

    result = Integrations::WhatsappNumberChecker::Client.new.check([contact.phone_number])
    exists = result[contact.phone_number]
    return if exists.nil? # servico indisponivel/nao configurado — nao grava nada, sem selo

    contact.update!(
      custom_attributes: contact.custom_attributes.merge(
        'whatsapp_verification' => { 'exists' => exists, 'checked_at' => Time.current }
      )
    )
  rescue StandardError => e
    Rails.logger.warn("[Contacts::WhatsappPresenceCheckJob] contact_id=#{contact_id} failed: #{e.message}")
  end
end
