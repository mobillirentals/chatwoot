class Api::V1::Accounts::WhatsappBulkDispatchesController < Api::V1::Accounts::BaseController
  before_action :set_dispatch, except: [:index, :create, :template_spreadsheet]
  before_action :check_authorization

  def index
    @dispatches = Current.account.whatsapp_bulk_dispatches.order(created_at: :desc)
  end

  # No dispatch exists yet at this point in the wizard (upload step, right after choosing a
  # template) — the client already knows the variable count from the template it loaded, same
  # place WhatsAppCampaignForm gets it from for the label-based flow.
  def template_spreadsheet
    xlsx = WhatsappBulkDispatch::TemplateSpreadsheetService.new(variable_names: variable_names_param).call
    send_data xlsx, filename: 'modelo_disparo_em_massa.xlsx',
                    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  # Recipients only get materialized as real rows when DispatchService actually runs (immediate
  # send, or the scheduler firing later — see TriggerScheduledDispatchJob). Before that, a
  # `scheduled` dispatch has zero Recipient records, so the details dialog would show nothing
  # despite the file already being uploaded and validated. Re-read + re-validate it here (same
  # inputs DispatchService itself will use) purely to preview who'll receive it — nothing here is
  # persisted, so it can't drift from or duplicate what the real send creates later.
  def show
    return unless @dispatch.scheduled? && @dispatch.file.attached?

    parsed = WhatsappBulkDispatch::SpreadsheetReaderService.new(attachment: @dispatch.file).read
    validation = WhatsappBulkDispatch::ValidationService.new(
      rows: parsed[:rows], column_mapping: @dispatch.column_mapping, required_variable_names: @dispatch.variable_names
    ).call
    @preview_recipients = validation[:valid_rows]
  end

  # Uploads the file and returns headers + a suggested column mapping. Nothing is persisted as
  # column_mapping yet — that only happens once the operator confirms it in #update. `variable_names`
  # comes from the client because it already knows the chosen template's variables (same place
  # WhatsAppCampaignForm already gets them from, for the label-based campaign flow).
  def create
    @dispatch = Current.account.whatsapp_bulk_dispatches.create!(dispatch_params)
    @dispatch.file.attach(params[:file])

    parsed = WhatsappBulkDispatch::SpreadsheetReaderService.new(attachment: @dispatch.file).read
    mapper = WhatsappBulkDispatch::ColumnMapperService.new(headers: parsed[:headers], variable_names: variable_names_param)

    @headers = parsed[:headers]
    @suggested_mapping = mapper.suggested_variable_mapping
    @suggested_phone_column = mapper.suggested_phone_column
  end

  # Persists the operator-confirmed column_mapping, then re-validates the file against it so the
  # wizard can show counts, rejected rows and a real rendered preview before anything is sent.
  def update
    @dispatch.update!(column_mapping: column_mapping_params)

    parsed = WhatsappBulkDispatch::SpreadsheetReaderService.new(attachment: @dispatch.file).read
    @validation = WhatsappBulkDispatch::ValidationService.new(
      rows: parsed[:rows], column_mapping: @dispatch.column_mapping, required_variable_names: @dispatch.variable_names
    ).call

    @preview = WhatsappBulkDispatch::PreviewService.new(
      dispatch: @dispatch, valid_rows: @validation[:valid_rows], template_params: @dispatch.liquid_template_params
    ).call
  end

  # Same split as Campaign#trigger! / TriggerScheduledItemsJob: send right away, or park it as
  # `scheduled` for the same 5-minute scheduler job that already picks up one-off campaigns.
  def confirm
    @dispatch.update!(scheduled_at: params[:scheduled_at]) if params[:scheduled_at].present?

    if @dispatch.scheduled_at.present? && @dispatch.scheduled_at.future?
      @dispatch.update!(status: :scheduled)
    else
      WhatsappBulkDispatch::DispatchService.new(dispatch: @dispatch).call
    end
  end

  def destroy
    @dispatch.destroy!
    head :ok
  end

  private

  # Named set_dispatch, not dispatch — ActionController::Metal already defines #dispatch as its
  # own core request-dispatching method, and a before_action of that name silently called the
  # wrong one (NoMethodError: private method 'dispatch' called), never reaching any action.
  def set_dispatch
    @dispatch = Current.account.whatsapp_bulk_dispatches.find(params[:id])
  end

  def dispatch_params
    params.permit(:title, :inbox_id, :template_name, :template_namespace, :template_language, :scheduled_at)
          .merge(sender: Current.user)
  end

  def variable_names_param
    Array(params[:variable_names])
  end

  def column_mapping_params
    params.require(:column_mapping).permit!
  end
end
