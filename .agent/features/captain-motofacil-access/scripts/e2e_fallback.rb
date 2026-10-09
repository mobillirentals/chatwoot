# Fallback da IA (11/09/2026). Rodar com a IA "fora": endpoint local apontando para um endereco inacessivel.
# C) conversa em andamento (o assistente ja tinha respondido) -> atendente, com nota para o time
# D) conversa parada (o job de resposta nunca rodou) -> a varredura aplica o fallback (menu, por ser conversa nova)
account = Account.find(47)
inbox = Inbox.find(95)
assistant = inbox.captain_assistant

new_conversation = lambda do |name|
  contact = account.contacts.create!(name: "E2E #{name}")
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
end

show = lambda do |conv, since_id|
  conv.messages.where('id > ?', since_id).reorder(:id).each do |m|
    tag = if m.private then 'NOTA INTERNA'
          elsif m.activity? then 'ATIVIDADE'
          elsif m.incoming? then 'CLIENTE'
          else "BOT (#{m.sender_type})"
          end
    buttons = m.content_type == 'input_select' ? " botoes=#{Array(m.content_attributes['items']).map { |i| i['title'] }}" : ''
    puts "#{tag}: #{m.content.to_s.tr("\n", ' ')[0, 220]}#{buttons}"
  end
  conv.reload
  active = Captain::Conversation::AiFallbackService.bot_flow_active?(conv.additional_attributes)
  puts "   -> status: #{conv.status} | time: #{conv.team&.name.inspect} | menu ativo: #{active} | bot_state: #{conv.additional_attributes['bot_state'].inspect}"
end

wait_reply = lambda do |conv, since_id, seconds|
  started = Time.current
  # rails runner roda com cache de consultas: sem uncached, o exists? repetia o resultado antigo ate o tempo acabar.
  answered = -> { Message.uncached { conv.messages.where('id > ?', since_id).where(message_type: :outgoing).exists? } }
  sleep 2 until answered.call || Time.current - started > seconds
  sleep 3
  puts "(resposta em #{(Time.current - started).round}s)"
end

puts '################ C) em andamento -> atendente'
conv = new_conversation.call('fallback_em_andamento')
conv.messages.create!(account: account, inbox: inbox, message_type: :outgoing, sender: assistant,
                      content: 'A loja de Vila Velha fica na Rua Dr. Jair de Andrade, 38. Posso ajudar em algo mais?')
since = conv.messages.maximum(:id)
conv.messages.create!(account: account, inbox: inbox, message_type: :incoming, sender: conv.contact, content: 'Sim, tenho outra dúvida')
wait_reply.call(conv, since, 150)
show.call(conv, since)
conv.reload
notes = conv.messages.where(private: true).pluck(:content)
puts "VERIFICA C: foi para atendente=#{conv.open?} | nota para o time=#{notes.include?(Captain::Conversation::AiFallbackService::TEAM_NOTE)} | sem menu=#{conv.messages.where(content_type: :input_select).none?}"

puts "\n################ D) conversa parada -> varredura"
conv = new_conversation.call('fallback_parada')
# Mensagem criada com a conversa aberta, para o Captain nao ser acionado: simula o job de resposta que se perdeu.
conv.update!(status: :open)
conv.messages.create!(account: account, inbox: inbox, message_type: :incoming, sender: conv.contact, content: 'Oi, alguém aí?')
conv.update_columns(status: Conversation.statuses[:pending], waiting_since: 10.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
since = conv.messages.maximum(:id)
Captain::UnansweredConversationsFallbackJob.perform_now
show.call(conv, since)
conv.reload
puts "VERIFICA D: menu enviado=#{conv.messages.where(content_type: :input_select).exists?} | ainda pendente no menu=#{conv.pending?}"
puts "\nIA marcada como indisponivel agora: #{Captain::Conversation::AiFallbackService.ai_unavailable?}"
