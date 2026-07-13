# The CRM lookup costs 0.58s at the median and 1.48s for a customer with an active contract —
# and the slow case is precisely the customer who has an invoice to pay, i.e. the one the bot most
# needs to answer quickly. The old bot paid that cost on the greeting, blocking hello on Bitrix.
#
# Here it is paid off the critical path: a background job warms this cache when the customer's
# first message lands, so by the time the model decides to call crm_lookup the answer is already
# waiting. A cold cache is not an error — the tool just fetches live.
#
# Redis, not the conversation record. The profile used to live in conversation.additional_attributes,
# which looked free — until it turned out Captain's own prompt renders every additional_attribute
# verbatim (see prompts/snippets/conversation.liquid). The whole profile was being pasted into the
# system prompt on every turn, including the legacy BotFlow copy it carries: the model read
# "sua próxima multa vence em..." and repeated it to a customer whose charge was a contract penalty,
# then routed them to the traffic-fines team. crm_lookup exists so the model reads this record in one
# controlled shape; parking the raw hash in the prompt quietly took that job away from it.
class Captain::CrmProfileCache
  TTL = 30.minutes

  pattr_initialize [:conversation!]

  def fetch
    cached || refresh
  end

  def refresh
    phone = conversation.contact&.phone_number.presence
    return nil if phone.blank?

    profile = ::Crm::ClientProfileService.new(phone, include_payments: false).perform
    store(profile)
    profile
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    nil
  end

  # symbolize_names, not symbolize_keys: the profile is nested (next_payment, overdue_payments), and
  # a shallow symbolize left those inner hashes string-keyed — crm_lookup's payment[:value] then read
  # nil and quoted the customer R$ 0,00 off a warm cache.
  def cached
    raw = ::Redis::Alfred.get(cache_key)
    return nil if raw.blank?

    JSON.parse(raw, symbolize_names: true)
  rescue JSON::ParserError
    nil
  end

  private

  def cache_key
    format(::Redis::Alfred::CAPTAIN_CRM_PROFILE_KEY, conversation_id: conversation.id)
  end

  def store(profile)
    ::Redis::Alfred.setex(cache_key, profile.to_json, TTL)
  end
end
