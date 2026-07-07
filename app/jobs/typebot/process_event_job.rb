class Typebot::ProcessEventJob < ApplicationJob
  queue_as :default

  def perform(payload, typebot_id)
    Typebot::BridgeService.new(payload, typebot_id).perform
  end
end
