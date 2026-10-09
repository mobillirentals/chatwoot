require 'json'
NAME = ENV.fetch('E2E_NAME')
LINES = JSON.parse(ENV.fetch('E2E_LINES'))
EXPECT = JSON.parse(ENV.fetch('E2E_EXPECT', '[]'))
FORBID = JSON.parse(ENV.fetch('E2E_FORBID', '[]'))
account = Account.find(47)
inbox = Inbox.find(95)
contact = account.contacts.create!(name: "E2E #{NAME}")
ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
puts "CONV_ID=#{conv.id} | conversa ##{conv.display_id} | #{NAME}"

last_seen = conv.messages.maximum(:id).to_i
say = lambda do |text|
  incoming = conv.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: text, sender: contact)
  puts "\nCLIENTE: #{text}"
  last_seen = incoming.id
  started = Time.current
  loop do
    sleep 2
    answered = conv.messages.where('id > ?', last_seen).where(message_type: :outgoing, private: false).exists?
    break if answered || !conv.reload.pending? || Time.current - started > 120
  end
  sleep 4
  replies = conv.messages.where('id > ?', last_seen).where(message_type: [:outgoing, :activity]).reorder(:id).to_a
  replies.each do |m|
    tag = if m.private then 'NOTA INTERNA'
          elsif m.message_type == 'activity' then 'ATIVIDADE'
          else "BOT (#{(m.created_at - started).round}s)"
          end
    puts "#{tag}: #{m.content.to_s.tr("\n", ' ')[0, 400]}"
  end
  puts '(sem resposta em 120s)' if replies.empty?
  conv.reload
  puts "   -> status: #{conv.status} | time: #{conv.team&.name.inspect}"
  last_seen = conv.messages.maximum(:id).to_i
  replies
end

replies = []
LINES.each do |line|
  break unless conv.reload.pending?

  replies = say.call(line)
end
2.times do
  break unless conv.reload.pending?

  said = replies.reject(&:private).map(&:content).join(' ')
  break unless said.match?(/algo mais|mais alguma|posso ajudar/i)

  replies = say.call('Não, era só isso. Obrigado!')
end

conv.reload
bot_text = conv.messages.where(message_type: :outgoing, private: false).pluck(:content).join("\n")
puts "\n=== VERIFICACOES (#{NAME}) ==="
EXPECT.each { |s| puts "menciona #{s.inspect}: #{bot_text.downcase.include?(s.downcase)}" }
FORBID.each { |s| puts "NAO menciona #{s.inspect}: #{!bot_text.downcase.include?(s.downcase)}" }
puts "JSON cru: #{bot_text.include?('"response"')}"
puts "status final: #{conv.status} | time: #{conv.team&.name.inspect}"
