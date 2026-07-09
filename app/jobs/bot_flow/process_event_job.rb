class BotFlow::ProcessEventJob < ApplicationJob
  queue_as :default

  def perform(payload, typebot_id)
    BotFlow::BridgeService.new(payload, typebot_id).perform
  end
end
