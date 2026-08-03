class BotFlow::ProcessEventJob < ApplicationJob
  queue_as :default

  def perform(payload, bot_id)
    BotFlow::BridgeService.new(payload, bot_id).perform
  end
end
