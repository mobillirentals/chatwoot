# =============================================================
# Mobílli Rentals — Setup Script
# Execução: bundle exec rails runner scripts/setup_mobilli.rb
#
# PRÉ-REQUISITO: conta criada via scripts/create_admin.rb
# =============================================================

account = Account.first
abort "ERRO: Nenhuma conta encontrada. Rode scripts/create_admin.rb primeiro." if account.nil?

puts "Conta encontrada: #{account.name} (id: #{account.id})"

# ------------------------------------------------------------------
# Times / Setores
# ------------------------------------------------------------------
TEAMS = [
  'Financeiro - Contas a Pagar',
  'Financeiro - Contas a Receber',
  'Pós-Venda',
  'Recolhimento',
  'Socorro',
  'Frota - Multas e Documentos',
  'TI',
  'Monitoramento',
  'Manutenção',
  'Sinistro',
  'Ouvidoria',
].freeze

puts "\nCriando times..."
TEAMS.each do |name|
  existing = account.teams.where('lower(name) = lower(?)', name).first
  if existing
    puts "  ↷ #{existing.name} (já existe)"
  else
    team = account.teams.create!(name: name)
    puts "  ✓ #{team.name}"
  end
end

# ------------------------------------------------------------------
# Resumo
# ------------------------------------------------------------------
puts "\n#{'='*50}"
puts "Setup concluído!"
puts "  Conta  : #{account.name}"
puts "  Times  : #{account.teams.count}"
puts "#{'='*50}"
puts "\nPróximos passos:"
puts "  1. Crie os agentes pelo painel (Settings → Agents)"
puts "  2. Atribua agentes aos times (Settings → Teams)"
