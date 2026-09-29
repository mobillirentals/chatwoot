module Enterprise::AccountUser
  def self.prepended(base)
    base.class_eval do
      before_validation :ensure_agent_role_with_custom_role
    end
  end

  def permissions
    custom_role.present? ? (custom_role.permissions + ['custom_role']) : super
  end

  private

  # Funcao personalizada so faz sentido sobre o papel de agente: administrador ignora qualquer
  # restricao (ve todas as caixas de entrada e todas as telas de configuracao). A tela de agentes
  # mostra apenas o nome da funcao quando ha custom_role_id, entao a combinacao "administrador com
  # funcao personalizada" fica invisivel: foi assim que uma administradora continuou vendo caixas
  # das quais nao era membro depois de aparecer como "Agente Mobilli" na lista.
  #
  # A tela de edicao manda so o custom_role_id ao escolher uma funcao personalizada (nao manda o
  # papel), entao a correcao mora aqui: vale pra UI, pra API e pra qualquer caminho futuro.
  def ensure_agent_role_with_custom_role
    self.role = :agent if custom_role_id.present? && administrator?
  end
end
