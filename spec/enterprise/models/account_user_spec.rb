require 'rails_helper'

RSpec.describe AccountUser do
  let(:account) { create(:account) }
  let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }

  describe 'funcao personalizada implica papel de agente' do
    it 'rebaixa o administrador que recebe uma funcao personalizada' do
      account_user = create(:account_user, account: account, role: :administrator)

      account_user.update!(custom_role: custom_role)

      expect(account_user.reload.role).to eq('agent')
      expect(account_user.custom_role).to eq(custom_role)
    end

    it 'nasce como agente quando ja e criado com funcao personalizada' do
      account_user = create(:account_user, account: account, role: :administrator,
                                           custom_role: custom_role)

      expect(account_user.role).to eq('agent')
    end

    it 'nao mexe no administrador sem funcao personalizada' do
      account_user = create(:account_user, account: account, role: :administrator)

      expect(account_user.reload.role).to eq('administrator')
    end

    it 'mantem as permissoes vindas da funcao personalizada' do
      account_user = create(:account_user, account: account, role: :administrator,
                                           custom_role: custom_role)

      expect(account_user.permissions).to include('conversation_manage', 'custom_role')
    end
  end
end
