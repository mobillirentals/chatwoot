# Renders the first few valid rows through the exact same Liquid pipeline the real send uses
# (Whatsapp::LiquidTemplateProcessorService), so "here's what Fulano will receive" is never a
# separate simulation that could drift from what actually gets sent. The result is the same
# `template_params` shape the campaign form's existing preview component already knows how to
# render into a chat bubble — reused on the frontend side, not reimplemented here.
class WhatsappBulkDispatch::PreviewService
  DEFAULT_SAMPLE_SIZE = 3

  pattr_initialize [:dispatch!, :valid_rows!, :template_params!, { sample_size: DEFAULT_SAMPLE_SIZE }]

  def call
    valid_rows.first(sample_size).map do |row|
      {
        phone_number: row[:phone_number],
        template_params: render(row[:variables])
      }
    end
  end

  private

  def render(variables)
    Whatsapp::LiquidTemplateProcessorService
      .new(campaign: dispatch, contact: nil, row: variables)
      .process_template_params(template_params)
  end
end
