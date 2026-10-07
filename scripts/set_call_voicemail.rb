# frozen_string_literal: true

# =============================================================================
# Recado de voz da chamada pela linha de comando: ver, trocar o áudio ou desligar.
#
# A tela (Caixas de Entrada → Chamadas) faz o mesmo. Este script serve para trocar rápido, em lote,
# ou gerar a voz a partir de um texto — o que a tela não faz.
#
# Ver o que está configurado hoje:
#   docker compose exec rails bundle exec rails runner scripts/set_call_voicemail.rb
#
# Trocar o áudio a partir de um texto (gera a voz na Azure, já em OGG/Opus):
#   docker compose exec -e TEXT="Olá! No momento..." rails bundle exec rails runner scripts/set_call_voicemail.rb
#
# Trocar por um arquivo pronto (OGG/Opus, menos de 60 s):
#   docker compose exec -e AUDIO=/tmp/aviso.ogg rails bundle exec rails runner scripts/set_call_voicemail.rb
#
# Variáveis:
#   PHONE            número da caixa (padrão: +5527992840261, a de Testes)
#   TEXT             texto a ser falado; gera o áudio na Azure
#   VOICE            voz da Azure (padrão: pt-BR-FranciscaNeural)
#   AUDIO            caminho de um .ogg pronto (tem precedência sobre TEXT)
#   TRIGGERS         REJECT e/ou TIMEOUT, separados por vírgula (padrão: REJECT)
#   TIMEOUT_SECONDS  0 a 30, usado quando TRIGGERS inclui TIMEOUT (padrão: 20)
#   DISABLE=1        desliga o recado
#
# ⚠️ Mexe na configuração REAL do número na Meta. Não há ambiente de teste para isso.
# =============================================================================

PHONE = ENV.fetch('PHONE', '+5527992840261')
VOICE = ENV.fetch('VOICE', 'pt-BR-FranciscaNeural')

canal = Channel::Whatsapp.find_by(phone_number: PHONE)
abort("Nenhuma caixa com o número #{PHONE}.") if canal.blank?
abort("A caixa #{PHONE} não é whatsapp_cloud — recado de voz só existe na API oficial.") unless canal.voice_calling_supported?

servico = Whatsapp::CallVoicemailService.new(channel: canal)

# A Azure devolve OGG/Opus direto, que é o formato que a Meta exige — sem conversão, e sem precisar
# de ffmpeg (que não existe em nenhum container).
def gerar_audio(texto, voz)
  chave = InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value
  ssml = <<~XML
    <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="pt-BR">
      <voice name="#{voz}">#{texto}</voice>
    </speak>
  XML
  resposta = HTTParty.post('https://eastus2.tts.speech.microsoft.com/cognitiveservices/v1',
                           headers: { 'Ocp-Apim-Subscription-Key' => chave,
                                      'Content-Type' => 'application/ssml+xml',
                                      'X-Microsoft-OutputFormat' => 'ogg-48khz-16bit-mono-opus',
                                      'User-Agent' => 'chatwoot-mobilli' },
                           body: ssml)
  abort("Falha ao gerar a voz: HTTP #{resposta.code} #{resposta.body.to_s[0, 200]}") unless resposta.success?

  destino = Rails.root.join('tmp', "aviso-#{Time.current.to_i}.ogg").to_s
  File.binwrite(destino, resposta.body)
  destino
end

# rubocop:disable Rails/Output
puts "\n  Caixa: #{canal.inbox.name} (#{PHONE})"
puts "  Recado hoje: #{servico.fetch}"

if ENV['DISABLE'].present?
  servico.disable
  puts "  -> desligado.\n\n"
  return
end

caminho = ENV['AUDIO'].presence || (ENV['TEXT'].present? ? gerar_audio(ENV.fetch('TEXT'), VOICE) : nil)

if caminho.blank?
  puts "\n  Nada a fazer. Passe TEXT=\"...\" para gerar a voz, AUDIO=/caminho.ogg para usar um arquivo,"
  puts "  ou DISABLE=1 para desligar.\n\n"
  return
end

abort("Arquivo não encontrado: #{caminho}") unless File.exist?(caminho)

media_id = File.open(caminho, 'rb') do |io|
  servico.enable(io: io, filename: File.basename(caminho),
                 triggers: ENV.fetch('TRIGGERS', 'REJECT').split(','),
                 timeout_seconds: ENV.fetch('TIMEOUT_SECONDS', '20'))
end

puts "  Áudio: #{caminho} (#{(File.size(caminho) / 1024.0).round} KB)"
puts "  -> ativo. media_id: #{media_id}"
puts "  Confira ligando para #{PHONE}.\n\n"
# rubocop:enable Rails/Output
