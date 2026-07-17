class Api::V1::Accounts::WhatsappBulkDispatchesController < Api::V1::Accounts::BaseController
  before_action :set_dispatch, except: [:index, :create]
  before_action :check_authorization

  def index
    @dispatches = Current.account.whatsapp_bulk_dispatches.order(created_at: :desc)
  end

  def show; end

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

  def confirm
    WhatsappBulkDispatch::DispatchService.new(dispatch: @dispatch).call
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
