class Webhooks::BotFlowController < ActionController::API
  def process_payload
    typebot_id = params[:typebot_id] # keeping param name or using standard
    BotFlow::ProcessEventJob.perform_later(params.to_unsafe_hash, typebot_id)
    head :ok
  end
end
