# Reads an uploaded CSV or XLSX (ActiveStorage attachment) into one uniform shape, so nothing
# downstream needs to know which format the operator uploaded.
class WhatsappBulkDispatch::SpreadsheetReaderService
  pattr_initialize [:attachment!]

  def read
    with_downloaded_file do |file|
      case extension
      when 'csv' then read_csv(file)
      when 'xlsx' then read_xlsx(file)
      else
        raise ArgumentError, "Unsupported spreadsheet type: .#{extension} (only .csv and .xlsx are supported)"
      end
    end
  end

  private

  def extension
    File.extname(attachment.filename.to_s).delete_prefix('.').downcase
  end

  # Same download-to-tempfile approach DataImportJob already uses for CSV — Roo needs a real
  # file path on disk for XLSX, so both formats go through the same mechanism.
  def with_downloaded_file(&)
    temp_dir = Rails.root.join('tmp/whatsapp_bulk_dispatch')
    FileUtils.mkdir_p(temp_dir)

    attachment.open(tmpdir: temp_dir) do |file|
      file.binmode
      yield file
    end
  end

  def read_csv(file)
    file.rewind
    raw_data = file.read
    utf8_data = raw_data.force_encoding('UTF-8')
    clean_data = utf8_data.valid_encoding? ? utf8_data : utf8_data.encode('UTF-16le', invalid: :replace, replace: '').encode('UTF-8')
    clean_data = clean_data.delete_prefix("\xEF\xBB\xBF")

    table = CSV.new(StringIO.new(clean_data), headers: true).read
    { headers: table.headers, rows: table.map(&:to_h) }
  end

  def read_xlsx(file)
    sheet = Roo::Spreadsheet.open(file.path, extension: :xlsx)
    headers = sheet.row(1).map(&:to_s)
    rows = (2..sheet.last_row).map { |i| headers.zip(sheet.row(i)).to_h }
    { headers: headers, rows: rows }
  end
end
