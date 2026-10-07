# Converte o tempo que o whisper devolve para o tempo real da chamada.
#
# O whisper **descarta o silêncio** e conta só a fala: num arquivo com 9 s de silêncio seguidos de
# fala, ele reporta o trecho em 0,00 s (medido). Para um arquivo isolado isso é inofensivo; para
# dois lados de uma mesma conversa é fatal, porque quem falou depois aparece no começo.
#
# Os intervalos medidos no navegador contam a mesma grandeza — só fala — mas sabem ONDE cada
# pedaço aconteceu. Então a conversão é por duração acumulada: "o segundo 7 de fala deste lado"
# vira o instante real correspondente, percorrendo os intervalos.
module Voice::SpeechTimeline
  module_function

  # `intervalos` é [{ 'start' => s, 'end' => s }] em ordem, em segundos.
  #
  # `borda` desempata quando o tempo cai exatamente na emenda entre dois intervalos: o FIM de um
  # trecho é o último instante em que ainda houve fala, e o INÍCIO do próximo é o primeiro
  # instante do intervalo seguinte. Sem essa distinção, uma frase que termina na emenda apareceria
  # começando depois de terminar.
  def to_real_time(segundos_na_fala, intervalos, borda: :end)
    return segundos_na_fala if intervalos.blank?

    restante = [segundos_na_fala, 0].max
    intervalos.each do |intervalo|
      duracao = intervalo['end'].to_f - intervalo['start'].to_f
      cabe = borda == :end ? restante <= duracao : restante < duracao
      return intervalo['start'].to_f + restante if cabe

      restante -= duracao
    end

    # Passou do fim: ancora no último instante de fala, nunca além dele.
    intervalos.last['end'].to_f
  end

  # Reposiciona os trechos de um lado, preservando a ordem e a duração de cada um.
  def place(segmentos, intervalos)
    return segmentos if intervalos.blank? || segmentos.blank?

    consumido = 0.0
    segmentos.sort_by { |s| s['start'].to_f }.map do |segmento|
      duracao = [segmento['end'].to_f - segmento['start'].to_f, 0].max
      inicio = to_real_time(consumido, intervalos, borda: :start)
      consumido += duracao
      segmento.merge('start' => inicio.round(2), 'end' => to_real_time(consumido, intervalos).round(2))
    end
  end
end
