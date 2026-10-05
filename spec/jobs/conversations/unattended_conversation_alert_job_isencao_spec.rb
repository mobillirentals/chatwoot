require 'rails_helper'

# Nem toda caixa quer o aviso automático. Numa caixa de vendas, "seu atendente se ausentou" soa
# como atendimento falhando onde ainda nem começou.
RSpec.describe Conversations::UnattendedConversationAlertJob do
  let(:account) { create(:account) }
  let(:atendimento) { create(:inbox, account: account) }
  let(:vendas) { create(:inbox, account: account) }
  let(:agente) { create(:user, account: account) }

  def conversa_esperando(inbox)
    create(:conversation, account: account, inbox: inbox, status: :open,
                          assignee: agente, waiting_since: 30.minutes.ago)
  end

  before do
    create(:inbox_member, inbox: atendimento, user: agente)
    create(:inbox_member, inbox: vendas, user: agente)
  end

  it 'avisa nas conversas de todas as caixas quando não há isenção' do
    duas = [conversa_esperando(atendimento), conversa_esperando(vendas)]

    avisadas = []
    allow(Conversations::UnattendedAlertService).to receive(:new) do |args|
      avisadas << args[:conversation].id
      instance_double(Conversations::UnattendedAlertService, perform: nil)
    end

    described_class.perform_now(account: account)

    expect(avisadas).to match_array(duas.map(&:id))
  end

  it 'deixa de fora a caixa listada na configuração' do
    da_atendimento = conversa_esperando(atendimento)
    conversa_esperando(vendas)
    create(:installation_config, name: 'UNATTENDED_ALERT_EXCLUDED_INBOX_IDS', value: vendas.id.to_s)
    GlobalConfig.clear_cache

    avisadas = []
    allow(Conversations::UnattendedAlertService).to receive(:new) do |args|
      avisadas << args[:conversation].id
      instance_double(Conversations::UnattendedAlertService, perform: nil)
    end

    described_class.perform_now(account: account)

    expect(avisadas).to eq([da_atendimento.id])
  end

  it 'aceita várias caixas separadas por vírgula, com espaço' do
    conversa_esperando(atendimento)
    conversa_esperando(vendas)
    create(:installation_config, name: 'UNATTENDED_ALERT_EXCLUDED_INBOX_IDS',
                                 value: "#{vendas.id}, #{atendimento.id}")
    GlobalConfig.clear_cache

    expect(Conversations::UnattendedAlertService).not_to receive(:new)

    described_class.perform_now(account: account)
  end

  # Config vazia é o estado normal da instalação: não pode virar `where.not(inbox_id: [])`, que
  # no Postgres descartaria tudo.
  it 'não isenta ninguém quando a configuração está vazia' do
    conversa = conversa_esperando(atendimento)
    create(:installation_config, name: 'UNATTENDED_ALERT_EXCLUDED_INBOX_IDS', value: '')
    GlobalConfig.clear_cache

    avisadas = []
    allow(Conversations::UnattendedAlertService).to receive(:new) do |args|
      avisadas << args[:conversation].id
      instance_double(Conversations::UnattendedAlertService, perform: nil)
    end

    described_class.perform_now(account: account)

    expect(avisadas).to eq([conversa.id])
  end
end
