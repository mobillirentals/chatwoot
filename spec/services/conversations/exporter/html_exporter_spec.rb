require 'rails_helper'

# A ligação entra no histórico como mensagem de conteúdo `voice_call`: o texto é só "Chamada do
# WhatsApp" e o que interessa — duração, sentido, quem falou — mora em content_attributes.
RSpec.describe Conversations::Exporter::HtmlExporter do
  let(:account) { create(:account) }
  let(:dados_padrao) do
    {
      'call_id' => 16, 'call_source' => 'whatsapp', 'call_direction' => 'outbound',
      'status' => 'completed', 'accepted_by' => { 'id' => agente.id, 'name' => agente.name },
      'duration_seconds' => 97
    }
  end
  let(:contact) { create(:contact, account: account) }
  let(:agente) { create(:user, account: account, name: 'Tecnologia da Informação') }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }

  # O exportador ordena a coleção, então precisa de uma relação e não de um array.
  let(:html) do
    described_class.new(contact: contact, conversations: Conversation.where(id: conversation.id),
                        exported_by: agente, account: account).perform
  end

  def criar_chamada(dados)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, sender: agente, content: 'Chamada do WhatsApp',
                     content_type: :voice_call, content_attributes: { data: dados })
  end

  it 'mostra a duração da chamada em vez de deixar só o texto da mensagem' do
    criar_chamada(dados_padrao)

    expect(html).to include('1 min 37 s')
  end

  it 'diz que a chamada foi efetuada quando partiu do agente' do
    criar_chamada(dados_padrao)

    expect(html).to include('Chamada efetuada').and include('Efetuada por Tecnologia da Informação')
  end

  # Trocar os dois faz o documento descrever errado quem procurou quem.
  it 'diz que foi recebida quando partiu do cliente' do
    criar_chamada(dados_padrao.merge('call_direction' => 'inbound'))

    expect(html).to include('Chamada recebida').and include('Atendida por')
  end

  it 'traduz o estado que vem do webhook' do
    criar_chamada(dados_padrao)

    expect(html).to include('concluída')
  end

  it 'mostra segundos quando a chamada foi curta' do
    criar_chamada(dados_padrao.merge('duration_seconds' => 17))

    expect(html).to include('17 s')
  end

  it 'omite a duração de uma chamada que não chegou a durar' do
    criar_chamada(dados_padrao.merge('duration_seconds' => 0, 'status' => 'missed'))

    expect(html).to include('não atendida')
    # A classe também existe na folha de estilo; o que não pode aparecer é o elemento.
    expect(html).not_to include('<span class="call-card__duration">')
  end

  context 'with a gravação anexada' do
    before do
      mensagem = criar_chamada(dados_padrao)
      mensagem.attachments.create!(account_id: account.id, file_type: :audio,
                                   file: { io: StringIO.new('audio'), filename: 'call-recording.ogg',
                                           content_type: 'audio/ogg' })
    end

    # O link é o que permite ouvir a ligação a partir do documento.
    it 'mostra a gravação como anexo com link' do
      expect(html).to include('Gravação da chamada')
      expect(html).to match(%r{href="https?://[^"]+"})
    end
  end

  # Áudio mandado pelo cliente não é gravação de chamada: nomear os dois igual confunde quem lê.
  it 'nao chama de gravação um áudio comum' do
    mensagem = create(:message, account: account, inbox: inbox, conversation: conversation,
                                message_type: :incoming, content: nil)
    mensagem.attachments.create!(account_id: account.id, file_type: :audio,
                                 file: { io: StringIO.new('audio'), filename: 'recado.ogg',
                                         content_type: 'audio/ogg' })

    expect(html).to include('recado.ogg')
    expect(html).not_to include('Gravação da chamada')
  end

  # O link de anexo do ActiveStorage vale 5 minutos por padrao: num documento guardado para
  # consulta depois, ele nasce morto.
  describe 'validade dos links' do
    before do
      mensagem = criar_chamada(dados_padrao)
      mensagem.attachments.create!(account_id: account.id, file_type: :audio,
                                   file: { io: StringIO.new('audio'), filename: 'call-recording.ogg',
                                           content_type: 'audio/ogg' })
    end

    it 'assina o link com a validade do documento, nao com os 5 minutos padrao' do
      token = html[%r{/rails/active_storage/disk/([A-Za-z0-9_=-]+)}, 1]
      payload = JSON.parse(Base64.decode64(token.split('--').first))
      expiracao = Time.zone.parse(payload.dig('_rails', 'exp'))

      expect(expiracao).to be > 40.days.from_now
      expect(expiracao).to be < 50.days.from_now
    end

    # Sem a data escrita, quem guardar o documento so descobre que expirou ao clicar.
    it 'informa no documento ate quando os links funcionam' do
      expect(html).to include('Os links de anexos e gravações deste documento funcionam até')
    end
  end
end
