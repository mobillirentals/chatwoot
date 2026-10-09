PHONE = '+5527999990002'.freeze
REDACT = Captain::Conversation::MessageHistoryBuilderService::REDACTED_FOR_LLM_KEY
account = Account.find(47)
inbox = Inbox.find(95)
if account.contacts.exists?(phone_number: PHONE)
  puts "ABORTADO: ja existe um contato com #{PHONE}. Nada foi alterado."
  exit
end
contact = account.contacts.create!(name: 'E2E caso 1 com encerramento', phone_number: PHONE)
ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
puts "CONV_ID=#{conv.id} | conversa ##{conv.display_id}"

def credential?(msg) = msg.additional_attributes.to_h[REDACT]

last_seen = conv.messages.maximum(:id).to_i
say = lambda do |text|
  incoming = conv.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: text, sender: contact)
  puts "\nCLIENTE: #{text}"
  last_seen = incoming.id
  started = Time.current
  loop do
    sleep 2
    answered = conv.messages.where('id > ?', last_seen).where(message_type: :outgoing, private: false).to_a.any? { |m| !credential?(m) }
    break if answered || !conv.reload.pending? || Time.current - started > 120
  end
  sleep 4
  replies = conv.messages.where('id > ?', last_seen).where(message_type: [:outgoing, :activity]).reorder(:id).to_a
  replies.each do |m|
    tag = if m.private then 'NOTA INTERNA'
          elsif m.message_type == 'activity' then 'ATIVIDADE'
          else "BOT (#{(m.created_at - started).round}s)"
          end
    body = credential?(m) ? '[CREDENCIAIS enviadas, senha ocultada]' : m.content.to_s.tr("\n", ' ')[0, 300]
    puts "#{tag}: #{body}"
  end
  puts '(sem resposta em 120s)' if replies.empty?
  puts "   -> status: #{conv.reload.status}"
  last_seen = conv.messages.maximum(:id).to_i
  replies
end

state = {}
replies = say.call('Oi, não consigo acessar a nova plataforma do Moto Fácil')
8.times do
  break unless conv.reload.pending?

  said = replies.reject(&:private).reject { |m| credential?(m) }.map(&:content).join(' ')
  sent = conv.messages.where("additional_attributes ->> ? = 'true'", REDACT).exists?
  text = if sent && said.match?(/algo mais|mais alguma|posso ajudar/i) && !state[:no]
           state[:no] = true
           'Não, era só isso. Obrigado!'
         elsif sent && !state[:ok]
           state[:ok] = true
           'Consegui entrar, muito obrigado!'
         elsif !sent && said.match?(/[\w.+-]+@[\w-]+\.[\w.]+/) && said.include?('?')
           'Sim, é esse mesmo'
         elsif !sent && said.match?(/receb/i) && said.match?(/credenc|instru/i) && !state[:received]
           state[:received] = true
           'Não recebi nada ainda'
         end
  break if text.nil?

  replies = say.call(text)
end

conv.reload
bot = conv.messages.where(message_type: :outgoing, private: false).reorder(:id).to_a.reject { |m| credential?(m) }
puts "\n=== VERIFICACOES (caso 1 com encerramento) ==="
puts "credenciais enviadas: #{conv.messages.where("additional_attributes ->> ? = 'true'", REDACT).count} (esperado: 1)"
puts "bot disse que as credenciais foram por e-mail: #{bot.any? { |m| m.content.to_s.match?(/(enviad\w*|mandad\w*)\s+(para o|ao|no)\s+(seu\s+)?e-?mail/i) }} (esperado: false)"
puts "perguntou se pode ajudar em algo mais: #{bot.any? { |m| m.content.to_s.match?(/algo mais|mais alguma|posso ajudar/i) }}"
puts "encerrou a conversa: #{conv.resolved?} (esperado: true)"
puts "ultima fala do bot: #{bot.last&.content.to_s.tr("\n", ' ')[0, 160].inspect}"
contact.update!(phone_number: nil)
