# Suggests which spreadsheet column feeds each template variable, and which column is the
# phone number — always a suggestion the operator confirms/edits in the mapping step, never
# applied blindly.
class WhatsappBulkDispatch::ColumnMapperService
  PHONE_COLUMN_HINTS = %w[telefone phone numero cellular celular whatsapp fone tel].freeze

  pattr_initialize [:headers!, :variable_names!]

  def suggested_variable_mapping
    variable_names.index_with { |variable_name| best_header_for(variable_name) }
  end

  def suggested_phone_column
    headers.find { |header| PHONE_COLUMN_HINTS.any? { |hint| normalize(header).include?(hint) } }
  end

  private

  def best_header_for(variable_name)
    needle = normalize(variable_name)
    return nil if needle.blank?

    headers.find { |header| normalize(header) == needle } ||
      headers.find { |header| normalize(header).include?(needle) || needle.include?(normalize(header)) }
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9]/, '')
  end
end
