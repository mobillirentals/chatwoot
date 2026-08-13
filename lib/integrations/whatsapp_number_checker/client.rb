# Cliente HTTP pro servico standalone whatsapp-number-checker/ (Node + Baileys). Nunca levanta
# excecao pra quem chama — se o servico nao estiver configurado, fora do ar, ou responder com
# erro, cada metodo devolve um valor "nao verificado" (nil/false/unavailable) e loga um warning.
# Essa e uma checagem consultiva em vários pontos da aplicacao; nenhum deles pode quebrar por
# causa de um servico auxiliar indisponivel.
class Integrations::WhatsappNumberChecker::Client
  TIMEOUT = 3 # segundos — checagem consultiva, tem que falhar rapido, nunca travar quem chama

  def self.configured?
    base_url.present?
  end

  def self.base_url
    ENV.fetch('WHATSAPP_CHECKER_URL', nil)
  end

  def health
    return unavailable_health unless self.class.configured?

    response = request(:get, '/health')
    return unavailable_health unless response&.success?

    response.parsed_response.symbolize_keys
  rescue StandardError => e
    log_warning('health', e)
    unavailable_health
  end

  # Bytes do PNG do QR code, ou nil se indisponivel/ja conectado/sem QR no momento.
  def qr
    return nil unless self.class.configured?

    response = request(:get, '/qr')
    return nil unless response&.success? && response.headers['content-type'].to_s.include?('image')

    response.body
  rescue StandardError => e
    log_warning('qr', e)
    nil
  end

  def logout
    return false unless self.class.configured?

    request(:post, '/logout')&.success? || false
  rescue StandardError => e
    log_warning('logout', e)
    false
  end

  # { "<numero>" => true/false/nil }, nil quando nao foi possivel verificar aquele numero
  # (servico indisponivel, nao configurado, ou erro na chamada) — nunca levanta excecao.
  def check(numbers)
    return unverified(numbers) unless self.class.configured?

    numbers.each_slice(50).with_object({}) { |batch, result| apply_batch_check(batch, result) }
  rescue StandardError => e
    log_warning('check', e)
    unverified(numbers)
  end

  private

  def apply_batch_check(batch, result)
    response = request(:post, '/check', body: { numbers: batch }.to_json)
    if response&.success?
      response.parsed_response['results'].each { |row| result[row['input']] = row['exists'] }
    else
      batch.each { |number| result[number] = nil }
    end
  end

  def request(method, path, body: nil)
    headers = { 'Content-Type' => 'application/json' }
    token = ENV.fetch('WHATSAPP_CHECKER_TOKEN', nil)
    headers['X-Checker-Token'] = token if token.present?

    HTTParty.public_send(method, "#{self.class.base_url}#{path}", headers: headers, body: body, timeout: TIMEOUT)
  end

  def unverified(numbers)
    numbers.index_with { nil }
  end

  def unavailable_health
    { whatsapp_connection: 'unavailable', whatsapp_number: nil }
  end

  def log_warning(action, error)
    Rails.logger.warn("[WhatsappNumberChecker::Client##{action}] #{error.class}: #{error.message}")
  end
end
