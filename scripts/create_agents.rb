# frozen_string_literal: true

# =============================================================================
# Cria agentes no Chatwoot para corresponder aos agentes do OctaDesk
# Uso: docker compose exec rails bundle exec rails runner scripts/create_agents.rb
#
# Na produção: inserir manualmente via UI (Configurações → Agentes)
# =============================================================================

ACCOUNT_ID = (ENV['ACCOUNT_ID'] || 1).to_i

AGENTS = [
  { name: 'Mobílli Rentals',                    email: 'ti@mobillirentals.com.br',          role: :administrator },
  { name: 'Kevin',                               email: 'kevin.mauro@mobillirentals.com.br',  role: :agent },
  { name: 'Leonardo Ramos de Lima',              email: 'leonardo.lima@mobillirentals.com.br', role: :administrator },
  { name: 'Yasmin',                              email: 'yasmin.juliao@mobillirentals.com.br', role: :agent },
  { name: 'Gustavo Oliveira',                    email: 'gustavo.dalcumune@mobillirentals.com.br', role: :agent },
  { name: 'Gustavo Vasquez',                     email: 'gustavo.vasquez@mobillirentals.com.br', role: :administrator },
  { name: 'Samanta Dutra',                       email: 'samanta.costa@mobillirentals.com.br', role: :agent },
  { name: 'Jonis Cavallini',                     email: 'jonis.cavallini@shalombr.com.br',    role: :administrator },
  { name: 'Hamayra',                             email: 'hamayra.silva@mobillirentals.com.br', role: :administrator },
  { name: 'Stéfani',                             email: 'stefani.brito@mobillirentals.com.br', role: :administrator },
  { name: 'Karina',                              email: 'karina.martins@mobillirentals.com.br', role: :agent },
  { name: 'Marco',                               email: 'marco.rodrigues@mobillirentals.com.br', role: :agent },
  { name: 'Rafael',                              email: 'rafael.ribeiro@mobillirentals.com.br', role: :agent },
  { name: 'Djalma Mariano',                      email: 'djalma.junior@mobillirentals.com.br', role: :administrator },
  { name: 'Gilmara',                             email: 'gilmara.lemos@shalombr.com.br',       role: :administrator },
  { name: 'Kaian Paganini Belmok',               email: 'kaian.belmok@mobillirentals.com.br',  role: :administrator },
  { name: 'Marcielly Sperandio dos Santos Barbosa', email: 'marcielly.sperandio@mobillirentals.com.br', role: :administrator },
].freeze

account = Account.find(ACCOUNT_ID)
created = 0
skipped = 0

AGENTS.each do |ag|
  user = User.find_by(email: ag[:email])

  if user.nil?
    temp_password = "Tmp@#{SecureRandom.hex(10)}1A!"
    user = User.create!(
      name: ag[:name],
      email: ag[:email],
      password: temp_password,
      password_confirmation: temp_password,

      confirmed_at: Time.current
    )
    puts "CRIADO:  #{ag[:name]} (#{ag[:email]})"
    created += 1
  else
    puts "EXISTE:  #{ag[:name]} (#{ag[:email]})"
    skipped += 1
  end

  # Garante vínculo com a conta
  AccountUser.find_or_create_by!(account: account, user: user) do |au|
    au.role = ag[:role]
  end
end

puts ''
puts "Criados: #{created} | Já existiam: #{skipped}"
puts 'Agentes vinculados ao inbox de importação:'

inbox = Inbox.find_by(account_id: account.id, name: 'OctaDesk - WhatsApp (Importado)')
if inbox
  AGENTS.each do |ag|
    user = User.find_by(email: ag[:email])
    next unless user

    InboxMember.find_or_create_by!(inbox: inbox, user: user)
  end
  puts "  #{AGENTS.size} agentes adicionados ao inbox '#{inbox.name}'"
else
  puts '  (inbox de importação não encontrado — rode o octadesk_import.rb primeiro)'
end
