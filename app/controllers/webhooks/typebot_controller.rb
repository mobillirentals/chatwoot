class Webhooks::TypebotController < ActionController::API
  def process_payload
    typebot_id = params[:typebot_id]
    return head :bad_request if typebot_id.blank?

    Typebot::ProcessEventJob.perform_later(params.to_unsafe_hash, typebot_id)
    head :ok
  end
end
