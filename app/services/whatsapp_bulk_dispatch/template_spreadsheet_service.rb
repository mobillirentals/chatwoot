# Builds a downloadable XLSX template for the bulk dispatch upload step: a header row with
# "telefone" + one "variavel_N" column per template variable, matching the same column-name
# hints ColumnMapperService already looks for — so re-uploading the filled template auto-suggests
# the mapping in the next step.
class WhatsappBulkDispatch::TemplateSpreadsheetService
  pattr_initialize [:variable_names!]

  def call
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: 'Modelo') { |sheet| sheet.add_row(header_row) }
    package.to_stream.read
  end

  private

  def header_row
    ['telefone', *variable_names.map { |name| "variavel_#{name}" }]
  end
end
