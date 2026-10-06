# frozen_string_literal: true

# =============================================================================
# Cria uma chamada FICTÍCIA com transcrição separada por locutor, para ver a tela
# sem precisar de WhatsApp, Meta ou microfone.
#
# Uso: docker compose exec rails bundle exec rails runner scripts/seed_call_transcript.rb
#
# No fim ele imprime o link da conversa. Só para desenvolvimento — nunca em produção.
# =============================================================================

abort('Este script é só para desenvolvimento.') if Rails.env.production?

conta = ENV['ACCOUNT_ID'].present? ? Account.find(ENV['ACCOUNT_ID'].to_i) : Account.first
abort('Nenhuma conta no banco.') if conta.blank?
conta.enable_features!('channel_voice')
conta.save!

# Qualquer caixa serve para VER a tela: o balão de chamada aparece pelo content_type da mensagem,
# e a transcrição por locutor aparece porque o Call traz os segmentos. Criar um canal de verdade
# tentaria falar com a Meta (o after_create sincroniza templates), o que não ajuda em nada aqui.
caixa = conta.inboxes.find_by(channel_type: 'Channel::Whatsapp') || conta.inboxes.first
abort('Nenhuma caixa na conta — crie uma pela tela antes.') if caixa.blank?

agente = conta.administrators.first || conta.users.first
abort('Nenhum usuário na conta — rode scripts/create_admin.rb antes.') if agente.blank?
InboxMember.find_or_create_by!(inbox: caixa, user: agente)

contato = Contact.find_or_create_by!(account: conta, phone_number: '+5527999990000') do |c|
  c.name = 'Jéssica Oliveira'
end
# Caixa de WhatsApp recusa source_id com o "+": a validação quer só dígitos.
contact_inbox = ContactInbox.find_or_create_by!(contact: contato, inbox: caixa,
                                                source_id: contato.phone_number.delete('+'))
conversa = Conversation.create!(account: conta, inbox: caixa, contact: contato,
                                contact_inbox: contact_inbox, assignee: agente)

mensagem = Message.create!(account: conta, inbox: caixa, conversation: conversa,
                           message_type: :incoming, content_type: :voice_call,
                           content: 'Chamada do WhatsApp')

# Mesma forma que o Voice::SpeakerTranscriptionService grava: um trecho por fala, ordenados no tempo.
#
# Com CALL_AUDIO apontando para a gravação real de 82 s, o texto abaixo é a transcrição que saiu
# dela do PRÓPRIO áudio pelo whisper, com os tempos que ele devolveu — então o realce acompanha a
# fala de verdade. Só a coluna de quem falou é atribuição manual: essa separação ainda não existe
# no dado, é justamente o que esta feature passa a produzir.
SEGMENTOS_REAIS = [
  ['contact', 0.00, 9.42, 'Eu botei um rato bem aqui em casa.'],
  ['agent', 9.42, 10.42, 'Onde?'],
  ['contact', 10.42, 11.42, 'Em um quintal.'],
  ['contact', 11.42, 12.90, 'A Luna prendeu ele ali no freezer.'],
  ['agent', 12.90, 13.90, 'Pra trás do freezer?'],
  ['contact', 13.90, 14.90, 'Embaixo do freezer.'],
  ['contact', 14.90, 15.90, 'Só vi ele passando, correndo, só.'],
  ['contact', 15.90, 16.90, 'E ela correndo atrás dele.'],
  ['contact', 16.90, 17.90, 'E ele rapidinho se escondeu.'],
  ['contact', 17.90, 18.90, 'Ele tava ali na cerâmica.'],
  ['agent', 18.90, 19.90, 'Mas ele é pequeno?'],
  ['contact', 19.90, 20.90, 'Ele é pequeno.'],
  ['contact', 20.90, 21.90, 'Ficava um dongo.'],
  ['agent', 21.90, 23.90, 'E aí?'],
  ['contact', 36.00, 37.00, 'Ela tá um tempão nervosa.'],
  ['contact', 37.00, 38.00, 'Com o negócio do tanque, não é?'],
  ['contact', 38.00, 39.12, 'Querendo pegar alguma coisa ali dentro.'],
  ['contact', 39.12, 41.36, 'Eu acho que era bem ele se escondendo.'],
  ['agent', 41.36, 46.64, 'Você vai pegar uma aí?'],
  ['contact', 46.64, 47.64, 'Vou.'],
  ['agent', 47.64, 48.64, 'Que horas só tem pra ele passar?'],
  ['agent', 50.84, 51.84, 'Você vai pegar uma aí?'],
  ['contact', 51.84, 52.84, 'Vou pegar ali embaixo.'],
  ['contact', 52.84, 53.84, 'Não tá aparecendo pra mim, não.'],
  ['agent', 53.84, 54.84, 'Hã?'],
  ['contact', 54.84, 55.84, 'Não tá aparecendo pra mim, não.'],
  ['agent', 55.84, 56.84, 'Será que não tá passando, não?'],
  ['contact', 56.84, 57.84, 'Eu acho que tá lá.'],
  ['contact', 58.84, 59.84, 'A conversação já caiu.'],
  ['agent', 59.84, 60.84, 'Eu vou pra lá, então.'],
  ['agent', 60.84, 61.84, 'Vê o partido.'],
  ['contact', 61.84, 62.84, 'É, eu olho nas partidas mesmo.'],
  ['contact', 62.84, 63.84, 'Eu tô vendo se vai passar alguma coisa.'],
  ['agent', 64.84, 65.84, 'Tá bom.'],
  ['contact', 84.84, 85.84, 'Beijo.']
].freeze

# Sem áudio real, uma conversa de atendimento inventada, na duração do WAV gerado mais abaixo.
SEGMENTOS_FICTICIOS = [
  ['contact', 0.0, 8.4, 'Oi, bom dia. Eu tô ligando por causa da parcela que não baixou no aplicativo.'],
  ['agent', 8.8, 12.6, 'Bom dia! Deixa eu conferir aqui pra você. Me confirma a placa, por favor?'],
  ['contact', 13.1, 17.9, 'É RQP 4D52. Paguei na sexta e até agora tá aparecendo em aberto.'],
  ['agent', 18.4, 26.2, 'Achei aqui. O pagamento consta como recebido, mas a baixa ficou presa. Vou pedir a correção agora.'],
  ['contact', 26.8, 30.1, 'E eu preciso fazer alguma coisa? Mandar comprovante de novo?'],
  ['agent', 30.5, 38.9, 'Não precisa, já tenho o seu. Em até um dia útil some do aplicativo. Se não sumir, me chama aqui mesmo.'],
  ['contact', 39.4, 42.0, 'Perfeito. E a vistoria do mês que vem, já tem data?'],
  ['agent', 42.6, 50.3, 'Ainda não abriu a agenda. Assim que abrir eu te aviso por aqui, antes de liberar pro geral.'],
  ['contact', 50.9, 53.2, 'Fechou então. Muito obrigada, viu.'],
  ['agent', 53.6, 56.0, 'Eu que agradeço. Bom dia!']
].freeze

AUDIO_REAL = ENV['CALL_AUDIO'].presence
SEGMENTOS = (AUDIO_REAL ? SEGMENTOS_REAIS : SEGMENTOS_FICTICIOS)
            .map { |speaker, inicio, fim, texto| { 'speaker' => speaker, 'start' => inicio, 'end' => fim, 'text' => texto } }

chamada = Call.create!(
  account: conta, inbox: caixa, conversation: conversa, contact: contato, message: mensagem,
  provider: :whatsapp, direction: :incoming, status: 'completed',
  provider_call_id: "wacid.dev.#{SecureRandom.hex(6)}", accepted_by_agent: agente,
  started_at: 1.minute.ago, duration_seconds: SEGMENTOS.last['end'].ceil
)
chamada.update!(transcript_segments: SEGMENTOS,
                transcript: SEGMENTOS.map { |s| "#{s['speaker'] == 'agent' ? agente.available_name : contato.name}: #{s['text']}" }.join("\n"))

# CALL_AUDIO=caminho/para/gravacao.ogg usa um arquivo de verdade — é o melhor teste, porque a fala
# bate com o texto e o clique para pular pode ser conferido de ouvido.
if AUDIO_REAL
  abort("Arquivo não encontrado: #{AUDIO_REAL}") unless File.exist?(AUDIO_REAL)

  mensagem.attachments.create!(account_id: conta.id, file_type: :audio,
                               file: { io: File.open(AUDIO_REAL), filename: 'call-recording.ogg',
                                       content_type: 'audio/ogg' })
else
  # Sem arquivo real, o player ainda precisa de algo com a MESMA duração das falas, senão não dá
  # para testar o pulo nem ver o cursor andar: um WAV com um bipe a cada 5 s. Cabeçalho e amostras
  # cruas, sem codificador — não há ffmpeg no container.
  taxa = 8000
  duracao = SEGMENTOS.last['end'].ceil + 1
  amostras = Array.new(taxa * duracao) do |i|
    segundo = i.to_f / taxa
    (segundo % 5) < 0.12 ? (Math.sin(2 * Math::PI * 880 * segundo) * 9000).to_i : 0
  end
  corpo = amostras.pack('s<*')
  cabecalho = ['RIFF', 36 + corpo.bytesize, 'WAVE', 'fmt ', 16, 1, 1, taxa, taxa * 2, 2, 16, 'data', corpo.bytesize]
              .pack('a4Va4a4VvvVVvva4V')

  mensagem.attachments.create!(account_id: conta.id, file_type: :audio,
                               file: { io: StringIO.new(cabecalho + corpo), filename: 'call-recording.wav',
                                       content_type: 'audio/wav' })
end

# rubocop:disable Rails/Output
puts "\n  Conversa criada: #{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/app/accounts/#{conta.id}/conversations/#{conversa.display_id}"
puts "  Chamada ##{chamada.id} com #{SEGMENTOS.size} falas (#{SEGMENTOS.count { |s| s['speaker'] == 'agent' }} do atendente)."
puts "  Caixa: #{caixa.name} (##{caixa.id}) · agente: #{agente.available_name}\n\n"
# rubocop:enable Rails/Output
