# Upstream's HandoffTool only opens the conversation for "a human" — it has no notion of which
# team should get it (its own source carries a TODO asking for exactly this). Triage is useless
# without it: the whole point is that a billing question reaches Financeiro and a contract
# question reaches Pós-Venda.
class Captain::Tools::AssignTeamTool < Captain::Tools::BasePublicTool
  include Captain::Tools::Concerns::BusinessHoursReadable

  description 'Transfer the conversation to the team that handles the subject, and hand it over to a human agent. ' \
              'Use this once you know which team the customer needs, or whenever you cannot resolve the request yourself.'
  param :team, type: 'string', desc: 'Name of the team that should take over the conversation'
  param :reason, type: 'string', desc: 'Short summary of what the customer needs, for the agent picking it up', required: false

  def perform(tool_context, team:, reason: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    target = find_team(team)
    return "No team named '#{team}'. Available teams: #{available_team_names}" if target.blank?

    log_tool_usage('assign_team', { conversation_id: conversation.id, team: target.name, reason: reason })

    transfer(conversation, target, reason)

    confirmation(conversation, target)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'Failed to transfer the conversation'
  end

  private

  # The transfer itself always succeeds — but outside opening hours it lands in an empty queue.
  # Telling the model so, right here, buys the warning for free: it is already reading this tool's
  # result, so no extra round-trip is spent, and the customer is not left waiting all night on a
  # cheerful "one moment!".
  def confirmation(conversation, team)
    done = "Conversation ##{conversation.display_id} transferred to the #{team.name} team."
    inbox = conversation.inbox
    return done unless hours_configured?(inbox) && !open_now?(inbox)

    "#{done} IMPORTANT: the team is CLOSED right now. Opening hours: #{schedule_text(inbox)}. " \
      'Tell the customer nobody is available at the moment and when the team will be back.'
  end

  def transfer(conversation, team, reason)
    note(conversation, reason) if reason.present?
    conversation.update!(team: team)
    # Leaves the bot queue so the team's agents actually see it. Already-open conversations
    # (a human is on it) keep their status; only the team changes.
    conversation.bot_handoff! if conversation.pending?
  end

  def note(conversation, reason)
    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: @assistant,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      content: reason
    )
  end

  # The model types the team name, so it will not match the database exactly: it writes
  # "Pos-Venda" for "pós-venda". Matching ignores case and accents, and an unmatched name comes
  # back with the real list attached, so the agent can correct itself on the next turn.
  def find_team(name)
    needle = normalize(name)
    return if needle.blank?

    teams = account_scoped(::Team).to_a
    teams.find { |team| normalize(team.name) == needle } ||
      teams.find { |team| normalize(team.name).include?(needle) || needle.include?(normalize(team.name)) }
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
  end

  def available_team_names
    account_scoped(::Team).pluck(:name).join(', ').presence || 'none'
  end

  def permissions
    %w[conversation_manage conversation_unassigned_manage conversation_participating_manage]
  end
end
