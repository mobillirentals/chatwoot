user = User.new(
  name:     ENV.fetch('ADMIN_NAME',  'Admin Mobílli'),
  email:    ENV.fetch('ADMIN_EMAIL', 'ti@mobillirentals.com.br'),
  password: ENV.fetch('ADMIN_PASSWORD'),
  type:     'SuperAdmin'
)
user.skip_confirmation!
user.save!

account = Account.create!(name: 'Mobílli Rentals')
AccountUser.create!(account: account, user: user, role: :administrator)

puts "Conta criada com sucesso"
puts "Email   : #{user.email}"
puts "Conta   : #{account.name} (id: #{account.id})"
