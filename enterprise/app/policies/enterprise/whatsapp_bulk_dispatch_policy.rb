module Enterprise::WhatsappBulkDispatchPolicy
  def index?
    @account_user.custom_role&.permissions&.include?('campaign_manage') || super
  end

  def show?
    @account_user.custom_role&.permissions&.include?('campaign_manage') || super
  end

  def create?
    @account_user.custom_role&.permissions&.include?('campaign_manage') || super
  end

  def update?
    @account_user.custom_role&.permissions&.include?('campaign_manage') || super
  end

  def confirm?
    @account_user.custom_role&.permissions&.include?('campaign_manage') || super
  end

  def destroy?
    @account_user.custom_role&.permissions&.include?('campaign_manage') || super
  end

  def template_spreadsheet?
    @account_user.custom_role&.permissions&.include?('campaign_manage') || super
  end
end
