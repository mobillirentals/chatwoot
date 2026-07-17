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

  # The variable identifiers in column_mapping (everything except the phone key). Real WhatsApp
  # templates seen in this account are all POSITIONAL ("1", "2", ... matching {{1}}, {{2}}), and
  # jsonb does not reliably preserve Hash key order — so when the keys are plain digit strings,
  # order is derived by sorting numerically instead of trusting iteration order. Named-parameter
  # templates (non-numeric keys) don't have this problem: Meta matches those by name, not position.
  def variable_names
    keys = column_mapping.keys - [WhatsappBulkDispatch::ValidationService::PHONE_KEY]
    keys.all? { |key| key.match?(/\A\d+\z/) } ? keys.sort_by(&:to_i) : keys
  end

  # Builds the same template_params shape Campaign#template_params uses, except every body
  # variable is a Liquid expression pointing at this dispatch's own row context (see
  # Whatsapp::LiquidTemplateProcessorService) instead of a value the operator typed by hand —
  # the mapping already says which variable is which, so there's nothing left to type.
  def liquid_template_params
    {
      'name' => template_name,
      'namespace' => template_namespace,
      'language' => template_language,
      'processed_params' => { 'body' => variable_names.index_with { |name| "{{ row.#{name} }}" } }
    }
  end

  private

  def validate_dispatch_inbox
    return if inbox.blank?
    return if inbox.inbox_type == 'Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'

    errors.add(:inbox, 'must be a WhatsApp Cloud API inbox')
  end
end
