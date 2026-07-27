# One row of the uploaded spreadsheet. Deliberately not a Contact: most recipients of a
# one-off blast never reply, and creating a permanent Contact for each of them would pollute
# the CRM with records nobody looks at again. If a recipient does reply, WhatsApp's own inbound
# pipeline (Whatsapp::IncomingMessageIdentifierHelper) finds-or-creates the Contact on its own.
# == Schema Information
#
# Table name: whatsapp_bulk_dispatch_recipients
#
#  id                        :bigint           not null, primary key
#  error_message             :string
#  phone_number              :string           not null
#  sent_at                   :datetime
#  status                    :integer          default("pending"), not null
#  variables                 :jsonb
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  whatsapp_bulk_dispatch_id :bigint           not null
#
# Indexes
#
#  index_wa_bulk_dispatch_recipients_on_dispatch_and_phone   (whatsapp_bulk_dispatch_id,phone_number) UNIQUE
#  index_wa_bulk_dispatch_recipients_on_dispatch_and_status  (whatsapp_bulk_dispatch_id,status)
#
class WhatsappBulkDispatch::Recipient < ApplicationRecord
  self.table_name = 'whatsapp_bulk_dispatch_recipients'

  belongs_to :whatsapp_bulk_dispatch

  # Only rows that pass validation ever become a Recipient — rejected/duplicate rows are never
  # persisted, they only show up in the downloadable failed-rows report (see ValidationService).
  enum status: { pending: 0, sent: 1, failed: 2 }

  validates :phone_number, presence: true
end
