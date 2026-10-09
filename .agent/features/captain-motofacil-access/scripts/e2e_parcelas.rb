MODE = ENV.fetch('E2E_MODE')
APP_PRINT = 'https://placehold.co/720x1280/png?text=Moto+F%C3%A1cil%0ACobran%C3%A7as%0A%0AParcela+05%2F09%0AEm+aberto'.freeze
RECEIPT = 'https://placehold.co/720x1000/png?text=Comprovante+PIX%0APagamento+efetuado%0A05%2F09%2F2026%0APara%3A+Mobilli+Rentals'.freeze
account = Account.find(47)
inbox = Inbox.find(95)
contact = account.contacts.create!(name: "E2E parcelas #{MODE}")
ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
puts "CONV_ID=#{conv.id} | conversa ##{conv.display_id} | #{MODE}"

last_seen = conv.messages.maximum(:id).to_i
last_incoming_id = nil
say = lambda do |text, image: nil, label: nil|
  incoming = conv.messages.new(account: account, inbox: inbox, message_type: :incoming, content: text, sender: contact)
  incoming.attachments.new(account_id: account.id, file_type: :image, external_url: image) if image
  incoming.save!
  last_incoming_id = incoming.id
  puts "\nCLIENTE: #{text}#{" [+ IMAGEM: #{label}]" if image}"
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

ids = {}
said_no_receipt = false
after_receipt_reply = nil
say.call('Oi, paguei a parcela do dia 05/09 e no aplicativo ainda aparece em aberto')
steps = if MODE == 'comprovante_depois_print'
          [[:receipt, 'É a parcela de 05/09. Segue o comprovante do pix', RECEIPT, 'comprovante do pix'],
           [:print, 'Aqui o print do aplicativo', APP_PRINT, 'print do app com a parcela 05/09 em aberto']]
        else
          [[:print, 'É a parcela de 05/09, segue o print do aplicativo', APP_PRINT, 'print do app com a parcela 05/09 em aberto']]
        end
replies = []
steps.each do |key, text, url, label|
  break unless conv.reload.pending?

  replies = say.call(text, image: url, label: label)
  ids[key] = last_incoming_id
  after_receipt_reply = replies.reject(&:private).map(&:content).join(' ') if key == :receipt
end
if conv.reload.pending? && replies.reject(&:private).map(&:content).join(' ').match?(/comprovante/i)
  said_no_receipt = true
  say.call('Não tenho o comprovante agora')
end

conv.reload
transfer = conv.messages.where(message_type: :activity).where('content ILIKE ?', '%suporte app%').reorder(:id).first
note = conv.messages.where(private: true).reorder(:id).last&.content.to_s
puts "\n=== VERIFICACOES (#{MODE}) ==="
if MODE == 'comprovante_depois_print'
  puts "depois do comprovante, NAO transferiu e pediu o print do app: #{(transfer.nil? || transfer.id > ids[:print].to_i) && after_receipt_reply.to_s.match?(/print|captura|tela/i)}"
  puts "  resposta apos o comprovante: #{after_receipt_reply.to_s.tr("\n", ' ')[0, 200].inspect}"
end
puts "transferiu so depois do print do app: #{transfer.present? && ids[:print].present? && transfer.id > ids[:print]}"
puts "precisou dizer que nao tem comprovante pra ser encaminhado: #{said_no_receipt}"
puts "nota interna: #{note.tr("\n", ' ')[0, 220].inspect}"
puts "status final: #{conv.status} | time: #{conv.team&.name.inspect} (esperado: open / suporte app)"
