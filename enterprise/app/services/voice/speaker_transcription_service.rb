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

  def montar_segmentos
    SPEAKERS.flat_map { |speaker, anexo| sem_eco(segmentos_de(speaker, call.public_send(anexo))) }
            .sort_by { |s| s['start'] }
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

  def segmentos_de(speaker, anexo)
    return [] if Llm::SpeechToTextService.too_large?(anexo.blob)

    resposta = Llm::SpeechToTextService.new(blob: anexo.blob, account: call.account, with_segments: true).perform
    Array(resposta['segments']).filter_map do |trecho|
      texto = trecho['text'].to_s.strip
      next if texto.blank?

      { 'speaker' => speaker, 'start' => trecho['start'].to_f.round(2), 'end' => trecho['end'].to_f.round(2), 'text' => texto }
    end
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
