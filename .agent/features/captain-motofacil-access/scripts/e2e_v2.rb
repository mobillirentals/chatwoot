MODE = ENV.fetch('E2E_MODE')
PHONE = ENV.fetch('E2E_PHONE')
REDACT = Captain::Conversation::MessageHistoryBuilderService::REDACTED_FOR_LLM_KEY
account = Account.find(47)
inbox = Inbox.find(95)

if account.contacts.exists?(phone_number: PHONE)
  puts "ABORTADO: ja existe um contato com #{PHONE}. Nada foi alterado."
  exit
end

contact = account.contacts.create!(name: "E2E v2 #{MODE}", phone_number: PHONE)
ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
puts "CONV_ID=#{conv.id} | conversa ##{conv.display_id} | cenario #{MODE} | telefone #{PHONE}"

def credential?(msg) = msg.additional_attributes.to_h[REDACT]

def show(msg)
  return msg.content.to_s.tr("\n", ' ')[0, 320] unless credential?(msg)

  "[CREDENCIAIS | link #{msg.content[%r{https?://\S+}]} | e-mail #{msg.content[/E-mail: (\S+)/, 1]} | senha #{msg.content[/Senha: (\S+)/, 1].to_s.length} caracteres, ocultada]"
end

last_seen = conv.messages.maximum(:id).to_i
say = lambda do |text|
  incoming = conv.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: text, sender: contact)
  puts "\nCLIENTE: #{text}"
  last_seen = incoming.id
  started = Time.current
  loop do
    sleep 2
    fresh = conv.messages.where('id > ?', last_seen).where(message_type: :outgoing).to_a
    break if fresh.any? { |m| !m.private && !credential?(m) } || !conv.reload.pending? || Time.current - started > 90
  end
  sleep 3
  replies = conv.messages.where('id > ?', last_seen).where(message_type: [:outgoing, :activity]).reorder(:id).to_a
  replies.each do |m|
    tag = if m.private then 'NOTA INTERNA'
          elsif m.message_type == 'activity' then 'ATIVIDADE'
          else "BOT (#{(m.created_at - started).round}s)"
          end
    puts "#{tag}: #{show(m)}"
  end
  puts '(sem resposta em 90s)' if replies.empty?
  last_seen = conv.messages.maximum(:id).to_i
  replies
end

next_text = lambda do |said, credentials_sent, state|
  if credentials_sent
    return nil if state[:after_credentials]

    state[:after_credentials] = true
    return MODE == 'nao_recebeu' ? 'Consegui entrar, muito obrigado!' : 'Tentei de novo com a senha nova e ainda não consegui'
  end
  return 'Sim, é esse mesmo' if said.match?(/[\w.+-]+@[\w-]+\.[\w.]+/) && said.include?('?')

  if said.match?(/receb/i) && said.match?(/credenc|instru/i) && !state[:answered_received]
    state[:answered_received] = true
    return MODE == 'nao_recebeu' ? 'Não recebi nada ainda' : 'Sim, recebi o e-mail com a senha'
  end
  if said.match?(/erro|print|tela|detalhe/i) && !state[:answered_error]
    state[:answered_error] = true
    return "Coloco o e-mail e a senha que recebi e aparece 'senha inválida'"
  end
  nil
end

state = {}
replies = say.call('Oi, não consigo acessar a nova plataforma do Moto Fácil')
8.times do
  break unless conv.reload.pending?

  said = replies.reject(&:private).reject { |m| credential?(m) }.map(&:content).join(' ')
  sent = conv.messages.where("additional_attributes ->> ? = 'true'", REDACT).exists?
  text = next_text.call(said, sent, state)
  break if text.nil?

  replies = say.call(text)
end

conv.reload
msgs = conv.messages.reorder(:id).to_a
bot_public = msgs.select { |m| m.message_type == 'outgoing' && !m.private && !credential?(m) }
cred = msgs.select { |m| credential?(m) }
pwd = cred.last&.content.to_s[/Senha: (\S+)/, 1]
email = cred.last&.content.to_s[/E-mail: (\S+)/, 1]
history = Captain::Conversation::MessageHistoryBuilderService.new(conversation: conv).perform.to_s
notes = msgs.select(&:private).map(&:content).join(' ')
first = bot_public.first&.content.to_s

puts "\n=== VERIFICACOES (#{MODE}) ==="
puts "1a fala do bot pergunta se recebeu as credenciais: #{first.match?(/receb/i) && first.match?(/credenc|instru/i)}"
puts "alguma fala do bot com JSON cru: #{bot_public.any? { |m| m.content.to_s.include?('"response"') }}"
if MODE != 'nao_recebeu'
  puts "antes de gerar, pediu detalhes do erro/print: #{cred.any? && bot_public.any? { |m| m.id < cred.first.id && m.content.to_s.match?(/erro|print|tela|detalhe/i) }}"
end
question = cred.any? && bot_public.select { |m| m.id < cred.first.id && m.content.to_s.include?(email.to_s) }.last
answered = question && msgs.any? { |m| m.message_type == 'incoming' && m.id > question.id && m.id < cred.first.id }
puts "antes da senha, perguntou o e-mail e o cliente respondeu: #{answered ? true : false}"
puts "mensagens de credenciais: #{cred.size} (esperado: 1)"
puts "senha no historico da IA: #{pwd.present? && history.include?(pwd)} | nas falas do bot: #{pwd.present? && bot_public.map(&:content).join(' ').include?(pwd)} | em nota: #{pwd.present? && notes.include?(pwd)}"
puts "status final: #{conv.status} | time: #{conv.team&.name.inspect} | atendente: #{conv.assignee&.name.inspect}"
contact.update!(phone_number: nil)
puts "telefone do contato liberado (conversa ##{conv.display_id} fica no painel)"
