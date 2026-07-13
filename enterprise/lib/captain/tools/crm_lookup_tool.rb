# Reuses the same CRM lookup the BotFlow bot already relies on (Bitrix deal + Asaas invoices),
# so Captain and the bot always tell the customer the same thing.
#
# This exists to stop the assistant from guessing. Anything about the customer's own contract,
# motorcycle or invoices is account-specific: without the record in front of it, a language model
# will happily invent a due date, and the customer will believe it.
class Captain::Tools::CrmLookupTool < Captain::Tools::BasePublicTool
  description "Look up this customer's rental record: active contract, motorcycle, overdue invoices and the next one due. " \
              'Call this BEFORE answering anything about their own contract, motorcycle or payments. Never guess those.'

  def perform(tool_context)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' if conversation.blank?

    log_tool_usage('crm_lookup', { conversation_id: conversation.id })

    # Warmed in the background when the customer's first message landed, so this is usually a
    # read off the conversation. A cold cache just fetches live — slower, never broken.
    profile = ::Captain::CrmProfileCache.new(conversation: conversation).fetch
    return 'The CRM could not be checked for this customer.' if profile.blank?
    return 'No CRM record found for this customer.' unless profile[:found]

    format_profile(profile)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'The CRM is unavailable right now, so the record could not be checked.'
  end

  private

  def format_profile(profile)
    [
      "Customer: #{profile[:name]}",
      "CPF: #{profile[:cpf].presence || 'not on file'}",
      contract_line(profile),
      motorcycle_line(profile),
      overdue_line(profile),
      next_payment_line(profile)
    ].compact.join("\n")
  end

  def contract_line(profile)
    return 'Active contract: no' unless profile[:active_contract]

    "Active contract: yes (started #{profile[:deal_start].presence || 'unknown date'})"
  end

  def motorcycle_line(profile)
    plate = profile[:current_motorcycle_plate].presence || profile[:contract_motorcycle_plate].presence
    model = profile[:current_motorcycle_model].presence || profile[:contract_motorcycle_model].presence
    return 'Motorcycle: none on the contract' if plate.blank? && model.blank?

    "Motorcycle: #{[model, plate].compact.join(' - ')}"
  end

  def overdue_line(profile)
    count = profile[:overdue_count].to_i
    return 'Overdue invoices: none' if count.zero?

    detail = Array(profile[:overdue_payments]).map { |p| payment_text(p) }.join('; ')
    "Overdue invoices: #{count}, totalling R$ #{format('%.2f', profile[:overdue_total].to_f)} (#{detail})"
  end

  def next_payment_line(profile)
    payment = profile[:next_payment]
    return 'Next invoice: none pending' if payment.blank?

    "Next invoice: #{payment_text(payment)}"
  end

  def payment_text(payment)
    text = "R$ #{format('%.2f', payment[:value].to_f)} due #{payment[:due_date]}"
    text += " - #{payment[:invoice_url]}" if payment[:invoice_url].present?
    text
  end

  def permissions
    %w[contact_manage]
  end
end
