# The CRM lookup costs 0.58s at the median and 1.48s for a customer with an active contract —
# and the slow case is precisely the customer who has an invoice to pay, i.e. the one the bot most
# needs to answer quickly. The old bot paid that cost on the greeting, blocking hello on Bitrix.
#
# Here it is paid off the critical path: a background job warms this cache when the customer's
# first message lands, so by the time the model decides to call crm_lookup the answer is already
# sitting on the conversation. A cold cache is not an error — the tool just fetches live.
class Captain::CrmProfileCache
  KEY = 'captain_crm'.freeze
  TTL = 30.minutes

  pattr_initialize [:conversation!]

  def fetch
    cached || refresh
  end

  def refresh
    phone = conversation.contact&.phone_number.presence
    return nil if phone.blank?

    profile = ::Crm::ClientProfileService.new(phone).perform
    store(profile)
    profile
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    nil
  end

  def cached
    entry = conversation.additional_attributes.to_h[KEY]
    return nil if entry.blank?
    return nil if stale?(entry['fetched_at'])

    entry['profile']&.symbolize_keys
  end

  private

  def stale?(fetched_at)
    return true if fetched_at.blank?

    Time.zone.parse(fetched_at.to_s) < TTL.ago
  rescue ArgumentError
    true
  end

  # update_column: this is a cache, not a business event. Going through update! would fire the
  # conversation callbacks and broadcast to every open dashboard on every warm-up.
  def store(profile)
    attributes = conversation.additional_attributes.to_h.merge(
      KEY => { 'profile' => profile, 'fetched_at' => Time.current.iso8601 }
    )
    conversation.update_column(:additional_attributes, attributes) # rubocop:disable Rails/SkipsModelValidations
  end
end
