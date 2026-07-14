# Bitrix + Asaas lookup used by BotFlow, extracted out of Engine so both the engine itself
# (cold-cache fallback) and CrmWarmupJob (background warm-up) call the exact same normalization.
class BotFlow::CrmLookup
  def self.fetch(conversation)
    new(conversation).fetch
  end

  def self.empty
    { found: false, first_name: nil, intro_message: nil, payment_message: nil,
      overdue_count: 0, overdue_total: 0.0, has_next_payment: false }
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def fetch
    phone = @conversation.contact&.phone_number
    return self.class.empty unless phone.present?

    normalize(Crm::ClientProfileService.new(phone).perform)
  rescue StandardError => e
    Rails.logger.error("[BotFlow] CRM fetch falhou: #{e.message}")
    self.class.empty
  end

  private

  def normalize(result)
    return self.class.empty unless result[:found]

    {
      found:            true,
      first_name:       result[:first_name],
      name:             result[:name],
      intro_message:    result[:intro_message],
      payment_message:  result[:payment_message],
      overdue_count:    result[:overdue_count].to_i,
      overdue_total:    result[:overdue_total].to_f,
      has_next_payment: result[:next_payment].present?
    }
  end
end
