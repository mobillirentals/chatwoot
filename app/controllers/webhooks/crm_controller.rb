class Webhooks::CrmController < ActionController::API
  before_action :authenticate!

  def client_profile
    phone = params[:phone].to_s.strip
    return render json: { error: 'phone obrigatório' }, status: :bad_request if phone.blank?

    result = Crm::ClientProfileService.new(phone).perform
    render json: result
  end

  private

  def authenticate!
    token = request.headers['X-CRM-Token'] || params[:token]
    return if token == ENV.fetch('CRM_PROXY_TOKEN', '')

    render json: { error: 'unauthorized' }, status: :unauthorized
  end
end
