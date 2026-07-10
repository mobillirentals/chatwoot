module Trash
  class TrashService
    pattr_initialize [:record!, :user, :ip]

    def perform
      record.transaction do
        record.trash!
        create_audit_log('trash')
      end
    end

    private

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
