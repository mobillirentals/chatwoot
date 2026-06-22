# =============================================================
# Teste de envio SMTP
# Execução: bundle exec rails runner scripts/test_smtp.rb
# =============================================================

require 'net/smtp'

to      = ENV.fetch('TEST_EMAIL', 'ti@mobillirentals.com.br')
from    = ENV.fetch('MAILER_SENDER_EMAIL', 'noreply@mobillirentals.com.br')
host    = ENV.fetch('SMTP_ADDRESS',  'smtp.azurecomm.net')
port    = ENV.fetch('SMTP_PORT',     '587').to_i
user    = ENV.fetch('SMTP_USERNAME', '')
pass    = ENV.fetch('SMTP_PASSWORD', '')

puts "SMTP Host    : #{host}:#{port}"
puts "From         : #{from}"
puts "To           : #{to}"
puts "Username     : #{user}"
puts "Password set : #{pass.present? ? 'SIM' : 'NÃO (vazio!)'}"
puts ""

message = <<~MSG
  From: Mobilli Rentals <#{from}>
  To: #{to}
  Subject: [Chatwoot] Teste de SMTP - #{Time.now.strftime('%d/%m/%Y %H:%M')}
  Content-Type: text/plain; charset=UTF-8

  Olá!

  Este é um e-mail de teste do Chatwoot Mobílli Rentals.
  Se você recebeu esta mensagem, o SMTP está funcionando corretamente. ✅

  Enviado em: #{Time.now}
MSG

begin
  smtp = Net::SMTP.new(host, port)
  smtp.enable_starttls
  smtp.start(ENV.fetch('SMTP_DOMAIN', 'mobillirentals.com.br'), user, pass, :login) do |s|
    s.send_message(message, from, to)
  end
  puts "✅ E-mail enviado com sucesso para #{to}"
rescue Net::SMTPAuthenticationError => e
  puts "❌ Erro de autenticação SMTP: #{e.message}"
  puts "   Verifique SMTP_USERNAME e SMTP_PASSWORD"
rescue Net::SMTPServerBusy, Net::SMTPFatalError, Net::SMTPUnknownError => e
  puts "❌ Erro SMTP: #{e.message}"
rescue => e
  puts "❌ Erro inesperado: #{e.class} — #{e.message}"
end
