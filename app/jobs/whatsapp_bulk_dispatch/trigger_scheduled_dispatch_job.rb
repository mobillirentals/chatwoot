# Mirrors Campaigns::TriggerOneoffCampaignJob — the coordinator (TriggerScheduledItemsJob)
# just enqueues one of these per due dispatch, this job does the actual claim + send.
class WhatsappBulkDispatch::TriggerScheduledDispatchJob < ApplicationJob
  queue_as :low

  def perform(dispatch)
    return unless claim(dispatch)

    WhatsappBulkDispatch::DispatchService.new(dispatch: dispatch).call
  end

  private

  # Multiple scheduler runs could pick up the same scheduled dispatch; lock before flipping
  # status so it's never claimed twice (mirrors Campaign#mark_processing!'s with_lock guard —
  # without it, two overlapping runs would both call DispatchService and double-insert recipients).
  def claim(dispatch)
    dispatch.with_lock do
      next false unless dispatch.scheduled?

      dispatch.update!(status: :processing)
    end
  end
end
