class Captain::SentimentService < Captain::BaseTaskService
  pattr_initialize [:account!, :conversation_display_id!]

  # Mirrors the 1-5 CSAT scale, so the dashboard renders it by reusing CSAT_RATINGS.
  SENTIMENT_RANGE = (1..5).freeze
  NEUTRAL = 3
  MESSAGE_LIMIT = 10
  MESSAGE_LENGTH_LIMIT = 200

  def perform
    cached_response = read_from_cache
    return cached_response if cached_response.present?

    messages = recent_customer_messages
    return nil if messages.blank?

    response = make_api_call(
      model: GPT_MODEL,
      messages: [
        { role: 'system', content: prompt_from_file('sentiment_analysis') },
        { role: 'user', content: format_messages(messages) }
      ]
    )
    return response if response[:error].present?

    result = build_result(response[:message])
    write_to_cache(result)
    result
  end

  private

  # Newest first, so the recency tags line up with the order the model reads them in.
  def recent_customer_messages
    return [] if conversation.blank?

    conversation.messages
                .where(message_type: :incoming)
                .where(private: false)
                .reorder(id: :desc)
                .limit(MESSAGE_LIMIT)
                .filter_map { |message| message.content_for_llm.presence }
  end

  def format_messages(messages)
    messages.each_with_index.map do |content, index|
      "#{recency_tag(index)} #{content.truncate(MESSAGE_LENGTH_LIMIT)}"
    end.join("\n")
  end

  def recency_tag(index)
    case index
    when 0 then '[MOST RECENT]'
    when 1, 2 then '[RECENT]'
    else '[EARLIER]'
    end
  end

  def build_result(content)
    parsed = parse_json_response(content)
    return { sentiment: NEUTRAL, confidence: 0.5 } if parsed.blank?

    {
      sentiment: normalize_sentiment(parsed['sentiment']),
      confidence: parsed['confidence'].to_f
    }
  end

  def parse_json_response(content)
    raw = content.to_s.strip
    json = raw.match(/```json\s*(.*?)\s*```/m)&.captures&.first || raw
    JSON.parse(json)
  rescue JSON::ParserError
    nil
  end

  def normalize_sentiment(value)
    sentiment = value.to_i
    SENTIMENT_RANGE.cover?(sentiment) ? sentiment : NEUTRAL
  end

  def cache_key
    return nil if conversation.blank?

    format(
      ::Redis::Alfred::OPENAI_CONVERSATION_KEY,
      event_name: event_name,
      conversation_id: conversation.id,
      updated_at: conversation.last_activity_at.to_i
    )
  end

  def read_from_cache
    return nil if cache_key.blank?

    cached = Redis::Alfred.get(cache_key)
    JSON.parse(cached, symbolize_names: true) if cached.present?
  rescue JSON::ParserError
    nil
  end

  def write_to_cache(response)
    Redis::Alfred.setex(cache_key, response.to_json) if cache_key.present?
  end

  def event_name
    'sentiment_analysis'
  end

  def use_account_openai_hook?
    true
  end

  def build_follow_up_context?
    false
  end

  # Sentiment runs on every inbound message. Drawing down captain_responses would starve the
  # quota that actually answers customers, and would block sentiment once that quota ran out.
  def counts_toward_usage?
    false
  end
end
