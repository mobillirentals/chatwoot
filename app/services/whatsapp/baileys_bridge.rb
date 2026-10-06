# Onde mora a ponte Baileys, para quem precisa dela ANTES de existir caixa.
#
# Depois que a caixa existe, a URL e o segredo vivem no provider_config dela — cada caixa pode
# apontar para uma ponte diferente. Mas a tela de conexao precisa falar com a ponte justamente
# para criar a caixa, entao esses dois valores tambem existem como configuracao da instalacao.
class Whatsapp::BaileysBridge
  include HTTParty

  TIMEOUT_SEGUNDOS = 15

  class << self
    def url
      GlobalConfig.get_value('BAILEYS_BRIDGE_URL').to_s.chomp('/')
    end

    def token
      GlobalConfig.get_value('BAILEYS_BRIDGE_TOKEN').to_s
    end

    # Segredo que a PONTE apresenta ao Chatwoot ao entregar mensagem recebida — caminho inverso do
    # bridge_token, e por isso um valor separado.
    def webhook_token
      GlobalConfig.get_value('BAILEYS_BRIDGE_WEBHOOK_TOKEN').to_s
    end

    def configurada?
      url.present? && token.present? && webhook_token.present?
    end
  end

  def get(caminho)
    HTTParty.get("#{self.class.url}#{caminho}", headers: headers, timeout: TIMEOUT_SEGUNDOS)
  end

  def post(caminho, body: nil)
    HTTParty.post("#{self.class.url}#{caminho}", headers: headers, body: body, timeout: TIMEOUT_SEGUNDOS)
  end

  private

  def headers
    { 'X-Bridge-Token' => self.class.token, 'Content-Type' => 'application/json' }
  end
end
