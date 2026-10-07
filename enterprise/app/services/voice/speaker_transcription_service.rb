# Transcreve os dois lados da chamada separadamente e os intercala numa conversa ordenada.
#
# Saber quem falou cada frase e informacao que o modelo de transcricao NAO devolve: ele recebe um
# arquivo e devolve texto corrido. A separacao vem de antes, da captura — o navegador do atendente
# grava o microfone e o fluxo remoto em arquivos distintos (nao ha ffmpeg no container para separar
# canais depois). Transcrevendo cada um com `verbose_json`, cada trecho chega com inicio e fim, e
# ordenar os dois conjuntos por tempo reconstroi o dialogo.
class Voice::SpeakerTranscriptionService
  pattr_initialize [:call!]

  def perform
    return if call.transcript_segments.present?
    return unless call.sides_recorded?
    return unless call.inbox.channel.transcription_enabled?
    return unless Llm::SpeechToTextService.available_for?(call.account)

    segmentos = montar_segmentos
    return if segmentos.blank?

    call.update!(transcript_segments: segmentos, transcript: texto_corrido(segmentos))
    descartar_gravacoes_dos_lados
    publicar
  end

  private

  SPEAKERS = { 'agent' => :recording_agent, 'contact' => :recording_contact }.freeze

  # Ordenar por `start` só faz sentido depois de pôr os dois lados no MESMO relógio: o whisper
  # descarta o silêncio inicial de cada arquivo, então o tempo que ele devolve para um lado não é
  # comparável com o do outro. Quem dá o relógio comum são os intervalos medidos no navegador.
  def montar_segmentos
    SPEAKERS.flat_map { |speaker, anexo| segmentos_no_relogio_real(speaker, anexo) }
            .sort_by { |s| s['start'] }
  end

  def segmentos_no_relogio_real(speaker, anexo)
    trechos = sem_eco(segmentos_de(speaker, call.public_send(anexo)))
    Voice::SpeechTimeline.place(trechos, call.speech_intervals[speaker])
  end

  # Quantas repeticoes seguidas da mesma frase ainda podem ser fala humana ("alo, alo, alo").
  ECO_TOLERADO = 2

  # O whisper entra em loop no silencio do fim da gravacao e repete a ultima frase ate o arquivo
  # acabar — num teste real, 66 copias de "E aí?". Repeticao identica e consecutiva nao e fala;
  # cortar o excesso e o que separa a conversa do ruido.
  def sem_eco(segmentos)
    repeticoes = 0
    anterior = nil

    segmentos.select do |trecho|
      repeticoes = trecho['text'].casecmp?(anterior.to_s) ? repeticoes + 1 : 0
      anterior = trecho['text']
      repeticoes < ECO_TOLERADO
    end
  end

  # O whisper INVENTA texto quando nao ha fala — num teste real devolveu telugo, "Thank you very
  # much." e letra de musica em cima de silencio. Ele mesmo entrega como reconhecer isso: cada
  # trecho vem com a probabilidade de nao haver fala ali, a confianca media, e a razao de
  # compressao (que dispara em repeticao). Sem esse corte, o lado que ficou calado aparece
  # "falando" na tela, porque as faixas sao desenhadas a partir dos segmentos.
  SEM_FALA = 0.6
  CONFIANCA_MINIMA = -1.0
  REPETICAO = 2.4

  def alucinacao?(trecho)
    return true if trecho['compression_ratio'].to_f > REPETICAO
    return false if trecho['no_speech_prob'].nil?

    trecho['no_speech_prob'].to_f > SEM_FALA && trecho['avg_logprob'].to_f < CONFIANCA_MINIMA
  end

  def trecho_de(speaker, trecho)
    { 'speaker' => speaker, 'start' => trecho['start'].to_f.round(2),
      'end' => trecho['end'].to_f.round(2), 'text' => trecho['text'].to_s.strip }
  end

  def segmentos_de(speaker, anexo)
    return [] if Llm::SpeechToTextService.too_large?(anexo.blob)

    resposta = Llm::SpeechToTextService.new(blob: anexo.blob, account: call.account, with_segments: true).perform
    Array(resposta['segments']).reject { |t| alucinacao?(t) || t['text'].to_s.strip.blank? }
                               .map { |t| trecho_de(speaker, t) }
  rescue Faraday::BadRequestError, Faraday::UnauthorizedError => e
    # Um lado que o modelo recusa (audio corrompido, credencial invalida) nao pode levar o outro
    # junto: sem nenhum segmento, o fluxo inteiro desiste e a mistura segue como estava.
    Rails.logger.warn("[VOICE] transcricao do lado #{speaker} falhou na chamada #{call.id}: #{e.class}")
    []
  end

  # O campo plano continua existindo para quem nao sabe de locutor: busca, Captain, e o proprio
  # player quando a tela antiga estiver aberta.
  def texto_corrido(segmentos)
    segmentos.map { |s| "#{nome_de(s['speaker'])}: #{s['text']}" }.join("\n")
  end

  def nome_de(speaker)
    speaker == 'agent' ? (call.accepted_by_agent&.available_name || 'Atendente') : (call.contact&.name || 'Cliente')
  end

  # Os lados sao insumo de transcricao, nao de reproducao — o player toca a mistura. Guardados,
  # triplicariam o armazenamento de cada chamada sem nunca mais serem lidos.
  def descartar_gravacoes_dos_lados
    call.recording_agent.purge_later
    call.recording_contact.purge_later
  end

  def publicar
    mensagem = call.message
    return if mensagem.blank?

    mensagem.reindex if ChatwootApp.advanced_search_allowed?
    mensagem.reload.send_update_event
  end
end
