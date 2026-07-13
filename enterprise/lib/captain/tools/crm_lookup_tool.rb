# Reuses the same Bitrix lookup the BotFlow bot relies on, so Captain and the bot never contradict
# each other about who the customer is.
#
# This exists to stop the assistant from guessing. Whether someone holds an active contract, and on
# which motorcycle, is account-specific: without the record in front of it, a language model will
# happily invent an answer and the customer will believe it.
class Captain::Tools::CrmLookupTool < Captain::Tools::BasePublicTool
  description "Look up this customer's rental record: whether they have an active contract, and which motorcycle is on it. " \
              'Call this BEFORE answering anything about their own contract or motorcycle. Never guess those. ' \
              'It does NOT return invoices, charges or payment links — those questions go to a human team.'

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

  # No invoices here on purpose. Charges are not modelled yet — their nature is inferred from free
  # text — so quoting one to a customer means quoting a guess. Money questions go to Financeiro.
  def format_profile(profile)
    [
      "Customer: #{profile[:name]}",
      "CPF: #{profile[:cpf].presence || 'not on file'}",
      contract_line(profile),
      motorcycle_line(profile)
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

  def permissions
    %w[contact_manage]
  end
end
