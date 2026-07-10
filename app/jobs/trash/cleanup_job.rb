class Trash::CleanupJob < ApplicationJob
  queue_as :low

  RETENTION_PERIOD = 30.days

  def perform
    # Purge conversations in the trash for longer than the retention period.
    # Note that Conversation.trashed uses unscoped, so it fetches deleted ones.
    Conversation.trashed.where('deleted_at < ?', RETENTION_PERIOD.ago).find_each do |conv|
      # Purge permanently (without a user/ip as it is an automated cleanup)
      Trash::PurgeService.new(record: conv, user: nil, ip: nil).perform
    end
  end
end
