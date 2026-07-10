module Enterprise::Audit::Conversation
  extend ActiveSupport::Concern

  # Conversations are audited through the trash lifecycle services
  # (Trash::TrashService / RestoreService / PurgeService), which emit
  # trash / restore / purge events with the acting user. We intentionally do
  # NOT audit the raw :destroy here — a permanent deletion (purge) would
  # otherwise produce duplicate rows (purge + destroy) in the audit log, and
  # cascade deletions (inbox/account) would flood it with per-conversation rows.
end
