# Caso 7: moto parada -> aceita o socorro -> manda so o PIN de localizacao do WhatsApp (sem texto).
# Confere se a IA leu o pin (patch no Captain::OpenAiMessageBuilderService) e transferiu para o socorro com a localizacao na nota.
account = Account.find(47)
inbox = Inbox.find(95)
contact = account.contacts.create!(name: 'E2E socorro_pin')
ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
puts "CONV_ID=#{conv.id} | conversa ##{conv.display_id} | socorro_pin"

wait_reply = lambda do |after_id|
  started = Time.current
  loop do
    sleep 2
    answered = conv.messages.where('id > ?', after_id).where(message_type: :outgoing, private: false).exists?
    break if answered || !conv.reload.pending? || Time.current - started > 120
  end
  sleep 4
  conv.messages.where('id > ?', after_id).where(message_type: %i[outgoing activity]).reorder(:id).each do |m|
    tag = if m.private then 'NOTA INTERNA'
          elsif m.activity? then 'ATIVIDADE'
          else 'BOT'
          end
    puts "#{tag}: #{m.content.to_s.tr("\n", ' ')[0, 400]}"
  end
  conv.reload
  puts "   -> status: #{conv.status} | time: #{conv.team&.name.inspect}"
end

say = lambda do |text|
  msg = conv.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: text, sender: contact)
  puts "\nCLIENTE: #{text}"
  wait_reply.call(msg.id)
end

say.call('Minha moto parou na rua e não liga mais')
say.call('Sim, quero o socorro') if conv.reload.pending?
if conv.reload.pending?
  msg = conv.messages.new(account: account, inbox: inbox, message_type: :incoming, content: nil, sender: contact)
  msg.attachments.new(account_id: account.id, file_type: :location, coordinates_lat: -20.1287, coordinates_long: -40.3078,
                      fallback_title: 'Av. Central, 100 - Laranjeiras, Serra')
  msg.save!
  puts "\nCLIENTE: [pin de localização: Av. Central, 100 - Laranjeiras, Serra]"
  wait_reply.call(msg.id)
end

conv.reload
notes = conv.messages.where(private: true).pluck(:content).join(' ')
bot = conv.messages.where(message_type: :outgoing, private: false).pluck(:content).join(' ')
puts "\n=== VERIFICACOES (socorro_pin) ==="
puts "time final socorro: #{conv.team&.name == 'socorro'}"
puts "nota com a localizacao: #{notes.include?('Central') || notes.include?('-20.1287')}"
puts "menciona bloqueio: #{bot.match?(/bloque/i)}"
puts "JSON cru: #{bot.include?('"response"')}"
