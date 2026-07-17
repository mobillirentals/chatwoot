# Materializes recipients from the dispatch's file + confirmed column_mapping, and kicks off
# sending. Re-reads and re-validates the file here rather than trusting whatever the wizard
# showed earlier — the file is the same, but nothing should be persisted based on a stale check.
class WhatsappBulkDispatch::DispatchService
  pattr_initialize [:dispatch!]

  def call
    parsed = WhatsappBulkDispatch::SpreadsheetReaderService.new(attachment: dispatch.file).read
    validation = WhatsappBulkDispatch::ValidationService.new(
      rows: parsed[:rows],
      column_mapping: dispatch.column_mapping,
      required_variable_names: dispatch.variable_names
    ).call

    create_recipients(validation[:valid_rows])
    attach_rejected_rows(validation[:rejected_rows])

    dispatch.update!(total_recipients: validation[:valid_rows].size, status: :processing)
    WhatsappBulkDispatch::SendBatchJob.perform_later(dispatch.id)
    dispatch
  end

  private

  def create_recipients(valid_rows)
    return if valid_rows.blank?

    recipients = valid_rows.map do |row|
      WhatsappBulkDispatch::Recipient.new(
        whatsapp_bulk_dispatch_id: dispatch.id, phone_number: row[:phone_number], variables: row[:variables]
      )
    end
    WhatsappBulkDispatch::Recipient.import(recipients)
  end

  def attach_rejected_rows(rejected_rows)
    return if rejected_rows.blank?

    headers = rejected_rows.flat_map(&:keys).uniq
    csv = CSV.generate(headers: true) do |out|
      out << headers
      rejected_rows.each { |row| out << headers.map { |header| row[header] } }
    end
    dispatch.failed_rows.attach(io: StringIO.new(csv), filename: 'linhas_rejeitadas.csv', content_type: 'text/csv')
  end
end
