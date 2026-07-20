# Bulk dispatch recipients never get a Contact/Conversation until they reply (deliberate — see
# WhatsappBulkDispatch's own docs). Their first reply lands with zero context otherwise: the
# agent sees "sim, pode ser" with no idea what template prompted it. This backfills the template
# as an activity note, dated when it actually went out, so it reads before the reply — only
# within REPLY_WINDOW of the original send (default 24h, WhatsApp's own customer-service-window
# length), so a reply to something unrelated weeks later doesn't get a stale, misleading context.
#
# Called from Conversation's own after_create (see enterprise/app/models/enterprise/conversation.rb)
# rather than anything on the incoming Message itself — see that file for why the timing matters.
#
# message_type: :activity (not :outgoing) is deliberate: Message#webhook_sendable? and
# AutomationRuleListener's ignore check both exclude activity messages, so this can never trigger
# SendReplyJob (no risk of a duplicate real WhatsApp send) or fire an automation rule/agent bot.
class WhatsappBulkDispatch::ReplyBackfillService
  REPLY_WINDOW = ENV.fetch('WHATSAPP_BULK_DISPATCH_REPLY_WINDOW_HOURS', 24).to_i.hours

  pattr_initialize [:conversation!]

  def call
    return unless conversation.inbox.inbox_type == 'Whatsapp'

    recipient = matching_recipient
    return if recipient.blank?

    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: recipient.whatsapp_bulk_dispatch.render_message(recipient.variables),
      created_at: recipient.sent_at,
      additional_attributes: { 'whatsapp_bulk_dispatch_id' => recipient.whatsapp_bulk_dispatch_id }
    )
  end

  private

  def matching_recipient
    phone_number = conversation.contact.phone_number
    return if phone_number.blank?

    WhatsappBulkDispatch::Recipient
      .joins(:whatsapp_bulk_dispatch)
      .where(phone_number: phone_number, status: :sent)
      .where(whatsapp_bulk_dispatch: { account_id: conversation.account_id, inbox_id: conversation.inbox_id })
      .where(sent_at: REPLY_WINDOW.ago..Time.current)
      .order(sent_at: :desc)
      .first
  end
end
