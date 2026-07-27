module Enterprise::Conversations::EventDataPresenter
  def push_data
    data = super
    data = data.merge(sla_data) if account.feature_enabled?('sla')
    data = data.merge(captain_sentiment: captain_sentiment) if account.feature_enabled?('captain_integration')
    data
  end

  private

  def sla_data
    sla_applicable = sla_applicable?

    {
      applied_sla: sla_applicable ? applied_sla&.push_event_data : nil,
      sla_events: sla_applicable ? sla_events.map(&:push_event_data) : [],
      sla_policy_id: sla_applicable ? sla_policy_id : nil
    }
  end
end
