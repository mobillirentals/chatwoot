# Disparo em massa de WhatsApp a partir de uma planilha (CSV/XLSX). Ao contrário de Campaign,
# não tem público persistente por etiqueta nem agendamento recorrente — é uma rajada única,
# com o arquivo de origem anexado, e os destinatários vivem em `recipients`, não em Contact.
class WhatsappBulkDispatch < ApplicationRecord
  has_one_attached :file
  has_one_attached :failed_rows

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true

  has_many :recipients, class_name: 'WhatsappBulkDispatch::Recipient', dependent: :destroy

  enum status: { draft: 0, processing: 1, completed: 2, failed: 3 }

  validates :title, presence: true
  validate :validate_dispatch_inbox

  private

  def validate_dispatch_inbox
    return if inbox.blank?
    return if inbox.inbox_type == 'Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'

    errors.add(:inbox, 'must be a WhatsApp Cloud API inbox')
  end
end
