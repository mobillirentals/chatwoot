class Account::UnattendedConversationAlertSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each(batch_size: 100) do |account|
      Conversations::UnattendedConversationAlertJob.perform_later(account: account)
    end
  end
end
Account::UnattendedConversationAlertSchedulerJob.prepend_mod_with('Account::UnattendedConversationAlertSchedulerJob')
