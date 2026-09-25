class ContactPolicy < ApplicationPolicy
  def index?
    true
  end

  def active?
    true
  end

  def import?
    @account_user.administrator?
  end

  def export?
    @account_user.administrator?
  end

  # Exportar transcrição e buscar no histórico do contato. Antes isto chamava
  # `@account_user.supervisor?`, um papel que nunca existiu no Chatwoot (o enum só tem agent e
  # administrator): para quem não fosse administrador a chamada estourava NoMethodError e virava
  # erro 500 em vez de uma negação limpa. Agora quem libera é a função personalizada.
  def export_conversations?
    @account_user.administrator? || pode_exportar_conversas?
  end

  def search_conversations?
    @account_user.administrator? || pode_exportar_conversas?
  end

  def search?
    true
  end

  def filter?
    true
  end

  def update?
    true
  end

  def contactable_inboxes?
    true
  end

  def destroy_custom_attributes?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def avatar?
    true
  end

  def destroy?
    @account_user.administrator?
  end

  private

  def pode_exportar_conversas?
    funcao = @account_user.custom_role
    funcao.present? && funcao.permissions.include?('conversation_export')
  end
end

ContactPolicy.prepend_mod_with('ContactPolicy')
