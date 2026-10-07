require 'rails_helper'

# O whisper conta só a fala: num arquivo com 9 s de silêncio seguidos de fala ele reporta o trecho
# em 0,00 s (medido contra o próprio modelo). Para um arquivo isolado tanto faz; para dois lados da
# mesma conversa é fatal — quem falou depois aparece no começo.
RSpec.describe Voice::SpeechTimeline do
  # Lado que ficou calado 10 s, falou 5 s, calou 20 s e falou mais 5 s.
  let(:intervalos) do
    [{ 'start' => 10.0, 'end' => 15.0 }, { 'start' => 35.0, 'end' => 40.0 }]
  end

  describe '.to_real_time' do
    it 'o início da fala cai no início do primeiro intervalo, não em zero' do
      expect(described_class.to_real_time(0, intervalos)).to eq(10.0)
    end

    it 'anda dentro do intervalo' do
      expect(described_class.to_real_time(3, intervalos)).to eq(13.0)
    end

    it 'pula o silêncio entre os intervalos' do
      expect(described_class.to_real_time(7, intervalos)).to eq(37.0)
    end

    # Exatamente na emenda: como FIM de um trecho é o último instante de fala do intervalo que
    # acabou; como INÍCIO do próximo é o primeiro instante do intervalo seguinte. Sem isso, uma
    # frase que termina na emenda apareceria começando depois de terminar.
    it 'desempata a emenda conforme seja fim ou início de trecho' do
      expect(described_class.to_real_time(5, intervalos)).to eq(15.0)
      expect(described_class.to_real_time(5, intervalos, borda: :start)).to eq(35.0)
    end

    it 'nunca ultrapassa o último instante de fala' do
      expect(described_class.to_real_time(999, intervalos)).to eq(40.0)
    end

    # Sem medida do navegador não há o que corrigir: devolve o tempo como veio, que é o
    # comportamento de antes desta feature.
    it 'devolve o tempo original quando não há intervalos' do
      expect(described_class.to_real_time(7, [])).to eq(7)
    end
  end

  describe '.place' do
    it 'reposiciona os trechos preservando ordem e duração' do
      segmentos = [
        { 'speaker' => 'agent', 'start' => 0.0, 'end' => 2.0, 'text' => 'Alô?' },
        { 'speaker' => 'agent', 'start' => 2.0, 'end' => 5.0, 'text' => 'Pois não?' }
      ]

      expect(described_class.place(segmentos, intervalos)).to eq(
        [
          { 'speaker' => 'agent', 'start' => 10.0, 'end' => 12.0, 'text' => 'Alô?' },
          { 'speaker' => 'agent', 'start' => 12.0, 'end' => 15.0, 'text' => 'Pois não?' }
        ]
      )
    end

    # É isto que conserta o diálogo: sem a correção, os dois lados começam em 0,0 e a ordem vira
    # sorteio. Com ela, quem falou primeiro aparece primeiro.
    it 'coloca na ordem certa quem falou depois' do
      cliente = described_class.place(
        [{ 'speaker' => 'contact', 'start' => 0.0, 'end' => 3.0, 'text' => 'Oi, bom dia.' }],
        [{ 'start' => 1.0, 'end' => 4.0 }]
      )
      atendente = described_class.place(
        [{ 'speaker' => 'agent', 'start' => 0.0, 'end' => 2.0, 'text' => 'Bom dia!' }],
        [{ 'start' => 6.0, 'end' => 8.0 }]
      )

      ordenado = (cliente + atendente).sort_by { |s| s['start'] }
      expect(ordenado.map { |s| s['speaker'] }).to eq(%w[contact agent])
    end

    it 'não mexe em nada quando não há medida do navegador' do
      segmentos = [{ 'speaker' => 'agent', 'start' => 0.0, 'end' => 2.0, 'text' => 'Alô?' }]

      expect(described_class.place(segmentos, nil)).to eq(segmentos)
    end

    # O whisper às vezes devolve trechos fora de ordem, e a conversão por duração acumulada exige
    # tempo crescente para não embaralhar o texto.
    it 'ordena os trechos antes de converter' do
      segmentos = [
        { 'speaker' => 'agent', 'start' => 2.0, 'end' => 4.0, 'text' => 'segundo' },
        { 'speaker' => 'agent', 'start' => 0.0, 'end' => 2.0, 'text' => 'primeiro' }
      ]

      expect(described_class.place(segmentos, intervalos).map { |s| s['text'] })
        .to eq(%w[primeiro segundo])
    end
  end
end
