module Enterprise::Conversation
  attr_accessor :captain_activity_reason, :captain_activity_reason_type

  def self.prepended(base)
    base.class_eval do
      # after_create, not after_create_commit: needs to save its own backfilled message (see
      # WhatsappBulkDispatch::ReplyBackfillService) BEFORE the real incoming message that's about
      # to follow (in Whatsapp::IncomingMessageBaseService#process_messages) begins its own save.
      #
      # Why this matters: Message#set_conversation_activity runs on every message's
      # after_create_commit and does conversation.update_columns(last_activity_at: created_at, ...)
      # — whichever message's after_commit callback fires LAST wins. Rails fires after_commit
      # callbacks in the order records registered with the current transaction, which happens at
      # the START of each record's own save (before its before_create even runs) — not in the
      # order rows get INSERTed. So creating the backfilled message from a hook that runs after
      # the real message's save has already started (e.g. a before_create on Message itself) is
      # too late: the real message already registered first and would lose to our backdated
      # timestamp. Creating it here, synchronously inside Conversation's own after_create — which
      # runs, and finishes, before IncomingMessageBaseService ever calls Message#save! for the
      # real incoming message — guarantees our message registers with the transaction first.
      after_create :backfill_whatsapp_bulk_dispatch_reply_context
    end
  end

  def dispatch_captain_inference_resolved_event
    dispatch_captain_inference_event(Events::Types::CONVERSATION_CAPTAIN_INFERENCE_RESOLVED)
  end

  def dispatch_captain_inference_handoff_event
    dispatch_captain_inference_event(Events::Types::CONVERSATION_CAPTAIN_INFERENCE_HANDOFF)
  end

  def list_of_keys
    super + %w[sla_policy_id]
  end

  # Surface call lifecycle changes to the FE: writes to additional_attributes
  # call_status/call_direction should rebroadcast conversation_updated.
  def allowed_keys?
    super || call_attributes_changed?
  end

  def with_captain_activity_context(reason:, reason_type:)
    previous_reason = captain_activity_reason
    previous_reason_type = captain_activity_reason_type

    self.captain_activity_reason = reason
    self.captain_activity_reason_type = reason_type
    yield
  ensure
    self.captain_activity_reason = previous_reason
    self.captain_activity_reason_type = previous_reason_type
  end

  private

  def dispatch_captain_inference_event(event_name)
    dispatcher_dispatch(event_name)
  end

  def call_attributes_changed?
    return false if previous_changes['additional_attributes'].blank?

    # Compare before/after values for call keys — checking key presence alone
    # rebroadcasts on any unrelated additional_attributes write once the keys exist.
    before, after = previous_changes['additional_attributes']
    %w[call_status call_direction].any? { |key| (before || {})[key] != (after || {})[key] }
  end

  def backfill_whatsapp_bulk_dispatch_reply_context
    ::WhatsappBulkDispatch::ReplyBackfillService.new(conversation: self).call
  end
end
