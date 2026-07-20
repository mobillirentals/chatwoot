# Sends one batch of pending recipients, then re-enqueues itself for the next batch — never one
# job trying to send an entire dispatch in a single run, so a large spreadsheet doesn't tie up a
# single worker for minutes and a crash mid-run only loses the current batch, not the rest.
class WhatsappBulkDispatch::SendBatchJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 50
  MAX_PER_MINUTE = ENV.fetch('WHATSAPP_BULK_RATE_PER_MINUTE', 60).to_i
  RETRY_DELAY = 10.seconds
  RATE_KEY = 'WHATSAPP_BULK_DISPATCH_RATE::%<inbox_id>s::%<minute>s'.freeze

  def perform(dispatch_id)
    dispatch = WhatsappBulkDispatch.find_by(id: dispatch_id)
    return if dispatch.blank?

    batch = dispatch.recipients.pending.order(:id).limit(BATCH_SIZE).to_a
    return finalize(dispatch) if batch.empty?

    batch.each do |recipient|
      if rate_limited?(dispatch.inbox_id)
        self.class.set(wait: RETRY_DELAY).perform_later(dispatch_id)
        return
      end

      send_to_recipient(dispatch, recipient)
    end

    if dispatch.recipients.pending.exists?
      self.class.perform_later(dispatch_id)
    else
      finalize(dispatch)
    end
  end

  private

  def send_to_recipient(dispatch, recipient)
    channel = dispatch.inbox.channel
    processed = Whatsapp::LiquidTemplateProcessorService
                .new(campaign: dispatch, contact: nil, row: recipient.variables)
                .process_template_params(dispatch.liquid_template_params)
    name, _namespace, lang_code, parameters = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: processed).call

    return mark_failed(dispatch, recipient, 'template not found, or all variables rendered blank') if name.blank?

    # send_template never raises on a rejected message — WhatsappCloudService#process_response
    # logs the Graph API error and returns nil, silently, by design (it's written for the
    # in-conversation reply path where a Message record already exists to carry the failure).
    # Caught locally: with a bad token every recipient here still came back `sent`, because
    # "no exception" isn't the same as "delivered". The truthy/blank message id is the only
    # signal send_template actually gives back.
    message_id = channel.send_template(recipient.phone_number, { name: name, namespace: nil, lang_code: lang_code, parameters: parameters }, nil)
    return mark_failed(dispatch, recipient, 'WhatsApp API rejected the message') if message_id.blank?

    recipient.update!(status: :sent, sent_at: Time.current)
    dispatch.increment!(:sent_count)
  rescue StandardError => e
    mark_failed(dispatch, recipient, e.message.to_s.truncate(500))
  end

  def mark_failed(dispatch, recipient, message)
    recipient.update!(status: :failed, error_message: message)
    dispatch.increment!(:failed_count)
  end

  # Simple per-minute counter, incremented per recipient (not reserved per batch up front) — a
  # recipient that gets rate-limited before sending gets retried next round and counted again,
  # which is a bit wasteful but never lets the count of actual sends exceed the cap. Good enough
  # without needing an atomic "reserve N slots" scheme.
  def rate_limited?(inbox_id)
    key = format(RATE_KEY, inbox_id: inbox_id, minute: Time.current.strftime('%Y%m%d%H%M'))
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 70) if count == 1
    count > MAX_PER_MINUTE
  end

  def finalize(dispatch)
    dispatch.update!(status: :completed)
  end
end
