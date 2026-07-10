module Trash
  class PurgeService
    pattr_initialize [:record!, :user, :ip]

    def perform
      record.transaction do
        track_deleted_email_messages
        DeleteObjectJob.perform_later(record, user, ip)
        create_audit_log('purge')
      end
    end

    private

    # Mirrors Conversations::DeleteService: on permanent deletion, record the IMAP
    # source ids so the email fetcher does not re-import already-purged messages.
    def track_deleted_email_messages
      return unless record.is_a?(Conversation) && record.inbox&.email?

      Imap::DeletedMessageTracker.new(inbox: record.inbox).record(record.messages.incoming.pluck(:source_id))
    end

    def create_audit_log(action)
      return unless defined?(Enterprise::AuditLog) && user.present?

      Enterprise::AuditLog.create(
        auditable: record,
        audited_changes: record.attributes,
        action: action,
        user: user,
        associated: record.account,
        remote_address: ip
      )
    end
  end
end
