# One row of the uploaded spreadsheet. Deliberately not a Contact: most recipients of a
# one-off blast never reply, and creating a permanent Contact for each of them would pollute
# the CRM with records nobody looks at again. If a recipient does reply, WhatsApp's own inbound
# pipeline (Whatsapp::IncomingMessageIdentifierHelper) finds-or-creates the Contact on its own.
class WhatsappBulkDispatch::Recipient < ApplicationRecord
  self.table_name = 'whatsapp_bulk_dispatch_recipients'

  belongs_to :whatsapp_bulk_dispatch

  # Only rows that pass validation ever become a Recipient — rejected/duplicate rows are never
  # persisted, they only show up in the downloadable failed-rows report (see ValidationService).
  enum status: { pending: 0, sent: 1, failed: 2 }

  validates :phone_number, presence: true
end
