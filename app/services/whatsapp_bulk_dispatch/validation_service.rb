# Pre-flight check over the parsed spreadsheet rows, before any Recipient is created and before
# any message is sent. Only rows that pass all checks become recipients; everything else is
# reported back so the operator sees it before confirming, not after messages start going out.
class WhatsappBulkDispatch::ValidationService
  PHONE_KEY = '__phone__'.freeze

  # column_mapping: { "<variable_name>" => "<spreadsheet header>", PHONE_KEY => "<phone header>" }
  pattr_initialize [:rows!, :column_mapping!, :required_variable_names!]

  def call
    seen_phones = {}
    valid_rows = []
    rejected_rows = []

    rows.each_with_index do |row, index|
      phone = normalize_phone(row[phone_header])
      variables = extract_variables(row)
      missing = missing_required_variables(variables)

      if phone.blank?
        rejected_rows << rejection(row, index, 'telefone ausente ou inválido')
      elsif missing.any?
        rejected_rows << rejection(row, index, "variável obrigatória vazia: #{missing.join(', ')}")
      elsif seen_phones[phone]
        rejected_rows << rejection(row, index, 'telefone duplicado na planilha')
      else
        seen_phones[phone] = true
        valid_rows << { phone_number: phone, variables: variables }
      end
    end

    { valid_rows: valid_rows, rejected_rows: rejected_rows, total: rows.size }
  end

  private

  def phone_header
    column_mapping[PHONE_KEY]
  end

  def extract_variables(row)
    required_variable_names.index_with { |name| row[column_mapping[name]] }
  end

  def missing_required_variables(variables)
    variables.select { |_name, value| value.blank? }.keys
  end

  # Spreadsheet phones show up local-format, no country code, often with spaces (e.g. the
  # sample data this feature was built for: "27 99670 2513"). Strip to digits, assume Brazil
  # if no country code is present, then reuse the normalizer that already fixes the old
  # 8-digit vs new 9-digit mobile ambiguity instead of re-solving that here.
  def normalize_phone(raw)
    return nil if raw.blank?

    digits = raw.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    digits = "55#{digits}" unless digits.start_with?('55')
    "+#{Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(digits)}"
  end

  def rejection(row, index, reason)
    row.merge('_row_number' => index + 2, '_error' => reason) # +2: header is row 1, data starts at row 2
  end
end
