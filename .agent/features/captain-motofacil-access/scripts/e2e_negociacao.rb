MODE = ENV.fetch('E2E_MODE')
account = Account.find(47)
inbox = Inbox.find(95)
contact = account.contacts.create!(name: "E2E negociacao #{MODE}")
ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
puts "CONV_ID=#{conv.id} | conversa ##{conv.display_id} | cenario #{MODE}"

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
    puts "#{tag}: #{m.content.to_s.tr("\n", ' ')[0, 320]}"
  end
  puts '(sem resposta em 120s)' if replies.empty?
  conv.reload
  puts "   -> status: #{conv.status} | time: #{conv.team&.name.inspect}"
  last_seen = conv.messages.maximum(:id).to_i
  replies
end

replies = say.call('Oi, queria mudar o dia do pagamento da semana para sábado. É possível?')
state = {}
6.times do
  break unless conv.reload.pending?

  said = replies.reject(&:private).map(&:content).join(' ')
  text = if MODE == 'so_pergunta'
           if said.match?(/algo mais|mais alguma|posso ajudar/i) && !state[:no]
             state[:no] = true
             'Não, era só isso. Obrigado!'
           elsif !state[:ok] && !state[:no]
             state[:ok] = true
             'Entendi, obrigado pela explicação.'
           end
         elsif !state[:exception]
           state[:exception] = true
           'Mas é só dessa vez, vocês não podem abrir uma exceção pra mim?'
         elsif !state[:contest]
           state[:contest] = true
           'Então quero contestar o valor da cobrança dessa semana, veio errado'
         end
  break if text.nil?

  replies = say.call(text)
end

conv.reload
bot = conv.messages.where(message_type: :outgoing, private: false).reorder(:id).to_a
puts "\n=== VERIFICACOES (#{MODE}) ==="
puts "alguma fala com JSON cru: #{bot.any? { |m| m.content.to_s.include?('"response"') }}"
if MODE == 'so_pergunta'
  puts "perguntou se pode ajudar em algo mais: #{bot.any? { |m| m.content.to_s.match?(/algo mais|mais alguma|posso ajudar/i) }}"
  puts "encerrou a conversa: #{conv.resolved?} (esperado: true) | time: #{conv.team&.name.inspect} (esperado: nil)"
  puts "ultima fala do bot (despedida): #{bot.last&.content.to_s.tr("\n", ' ')[0, 160].inspect}"
else
  puts "status/time final: #{conv.status} / #{conv.team&.name.inspect} (esperado: open / financeiro)"
end
