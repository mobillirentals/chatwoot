class Voice::SpeakerTranscriptionJob < ApplicationJob
  queue_as :low

  # Mesmo criterio do job de transcricao da chamada: audio que o modelo recusa ou credencial que ele
  # nega nunca passa numa nova tentativa — melhor desistir do que insistir contra a API.
  discard_on Faraday::BadRequestError, Faraday::UnauthorizedError do |job, error|
    contexto = {
      call_id: job.arguments.first,
      job_id: job.job_id,
      status_code: error.response&.dig(:status)
    }

    Rails.logger.warn("Discarding speaker transcription job: #{contexto}")
  end
  retry_on ActiveStorage::FileNotFoundError, wait: 2.seconds, attempts: 3
  # O deployment de transcricao tem capacidade pequena e os dois lados sobem juntos, entao 429 e
  # esperado, nao excecao. Espera crescente em vez de desistir.
  retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 5

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return if call.blank?

    Voice::SpeakerTranscriptionService.new(call: call).perform
  end
end
