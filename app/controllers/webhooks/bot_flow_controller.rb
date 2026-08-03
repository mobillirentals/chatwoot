class Webhooks::BotFlowController < ActionController::API
  def process_payload
    # Accepts bot_id (current) and typebot_id (kept for inboxes still configured
    # with the old Typebot-era webhook URL) — unused downstream either way.
    bot_id = params[:bot_id] || params[:typebot_id]
    BotFlow::ProcessEventJob.perform_later(params.to_unsafe_hash, bot_id)
    head :ok
  end
end
