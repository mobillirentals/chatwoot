# Mensagem que chega pela ponte Baileys.
#
# A ponte entrega no mesmo formato enxuto que o serviço base já entende (o do 360dialog:
# `contacts` e `messages` na raiz, sem o envelope `entry`/`changes` da Meta), então não há nada a
# traduzir aqui — como em Whatsapp::IncomingMessageService, a classe existe para dar nome ao
# caminho e ser o lugar onde mídia e recibo de entrega entram na próxima rodada.
class Whatsapp::IncomingMessageBaileysService < Whatsapp::IncomingMessageBaseService
end
