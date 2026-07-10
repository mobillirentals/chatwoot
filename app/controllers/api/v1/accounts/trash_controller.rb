class Api::V1::Accounts::TrashController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    # We fetch trashed conversations for the account.
    # Note that Trashable uses default_scope to filter out deleted records,
    # so we must use unscoped or .trashed (which uses unscoped internally)
    @conversations = current_account.conversations.trashed
                                    .includes(:contact, :inbox)
                                    .order(deleted_at: :desc)
                                    .page(params[:page])
  end

  def restore
    record = current_account.conversations.trashed.find(params[:id])
    Trash::RestoreService.new(record: record, user: Current.user, ip: request.ip).perform
    head :ok
  end

  # Read-only preview of a trashed conversation. The regular messages endpoint
  # looks the conversation up through the default scope (which hides trashed
  # records), so it 404s; here we fetch it via .trashed and reuse the standard
  # messages serialization so the preview modal can render it as-is.
  def messages
    @conversation = current_account.conversations.trashed.find(params[:id])
    @messages = MessageFinder.new(@conversation, params).perform
    render 'api/v1/accounts/conversations/messages/index'
  end

  private

  def check_authorization
    # We authorize the access. Admins and supervisors can manage trash.
    authorize Conversation, :manage_trash?
  end
end
