# Without this, the assistant has no idea what time it is: nothing about working hours ever
# reaches its prompt. It would cheerfully transfer a customer to Financeiro at 11pm with a
# "one moment!" and leave them waiting all night.
#
# The class is named for the tool id after String#classify runs on it, and classify SINGULARISES:
# an id of "business_hours" would look for BusinessHourTool, fail to constantize, and the tool
# would vanish from the assistant with no error at all. Hence "business_hours_check".
class Captain::Tools::BusinessHoursCheckTool < Captain::Tools::BasePublicTool
  include Captain::Tools::Concerns::BusinessHoursReadable

  description 'Check whether the human teams are available right now, and what the opening hours are. ' \
              'Use it when the customer asks when we are open, and before promising that someone will get back to them.'

  def perform(tool_context)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    inbox = conversation.inbox
    return 'No opening hours are configured, so assume the teams are available.' unless hours_configured?(inbox)

    log_tool_usage('business_hours', { inbox_id: inbox.id, open: open_now?(inbox) })

    "#{status_text(inbox)} Horário de atendimento: #{schedule_text(inbox)} (fuso #{inbox.timezone})."
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'Could not check the opening hours.'
  end

  private

  def status_text(inbox)
    open_now?(inbox) ? 'The teams are AVAILABLE right now.' : 'The teams are CLOSED right now.'
  end
end
