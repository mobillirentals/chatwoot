class WhatsappBulkDispatchPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def confirm?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def template_spreadsheet?
    @account_user.administrator?
  end
end

WhatsappBulkDispatchPolicy.prepend_mod_with('WhatsappBulkDispatchPolicy')
