require 'open-uri'
require 'base64'
require 'mini_magick'

module Conversations
  module Exporter
    class HtmlExporter < BaseExporter
      # Images are resized to fit within this box before base64 encoding. Keeps file size
      # manageable, and — importantly for print — MAX_IMAGE_HEIGHT keeps any single image
      # short enough to fit inside one A4 page's printable area (297mm - 15mm/20mm margins
      # ≈ 990px), leaving room for the rest of that page's content. This is what makes it safe
      # to give .attachment--image `page-break-inside: avoid` in show.html.erb — a tall
      # portrait screenshot at native size used to overflow one page's height, and the browser
      # printing engine can't honor "avoid" on a block taller than the page itself (it pushes
      # the whole thing to the next page anyway and still cuts it mid-image).
      MAX_IMAGE_WIDTH  = 800
      MAX_IMAGE_HEIGHT = 700
      IMAGE_QUALITY    = 75   # JPEG quality (1-100); 75 is visually lossless for documents
      EMBED_TIMEOUT    = 8    # seconds per image download

      # O link de anexo do ActiveStorage vale 5 minutos por padrão — num documento que é guardado
      # para consulta depois, ele nasce morto. 45 dias cobrem auditoria e disputa sem deixar a
      # gravação de um cliente acessível para sempre a quem receber o arquivo. O documento informa
      # a data de validade, então mudar este prazo muda o que está escrito lá.
      ATTACHMENT_LINK_TTL = 45.days

      # O webhook da Meta manda o estado em inglês; o documento é lido em português.
      CALL_STATUS_LABELS = {
        'completed' => 'concluída',
        'missed' => 'não atendida',
        'rejected' => 'recusada',
        'failed' => 'falhou',
        'busy' => 'ocupado',
        'no-answer' => 'não atendida',
        'canceled' => 'cancelada'
      }.freeze

      def perform
        sha = content_sha256(@conversations)
        render_html(sha)
      end

      private

      def render_html(sha)
        ApplicationController.render(
          template: 'conversation_exports/show',
          layout: false,
          assigns: {
            contact: @contact,
            conversations: decorated_conversations,
            exported_by: @exported_by,
            account: @account,
            generated_at: format_datetime(Time.current),
            links_valid_until: format_date(ATTACHMENT_LINK_TTL.from_now),
            sha256: sha,
            logo_svg: brand_logo_svg
          }
        )
      end

      # Lê o SVG da logo para embutir inline no cabeçalho (auto-contido no PDF).
      def brand_logo_svg
        path = Rails.root.join('public/brand-assets/logo.svg')
        File.exist?(path) ? File.read(path) : nil
      rescue StandardError => e
        Rails.logger.warn "[HtmlExporter] Could not read brand logo: #{e.message}"
        nil
      end

      def decorated_conversations
        @conversations.order(:created_at).map do |conv|
          {
            conversation: conv,
            channel: channel_name(conv),
            assignees: responsible_agents(conv),
            bot_first_response: bot_first_response_time(conv),
            agent_first_response: agent_first_response_time(conv),
            labels: conv.labels.join(', '),
            messages: decorated_messages(conv)
          }
        end
      end

      def decorated_messages(conv)
        conv.messages
            .where(content_type: displayable_content_types)
            .order(:created_at)
            .map { |msg| decorate_message(msg) }
      end

      def displayable_content_types
        # Exclude interactive bot messages and CSAT that add noise
        Message.content_types.except('input_text', 'input_textarea', 'input_email',
                                     'input_select', 'cards', 'form', 'input_csat',
                                     'integrations').values
      end

      def decorate_message(msg)
        {
          message: msg,
          id: msg.id,
          in_reply_to: msg.in_reply_to,
          sender: sender_name(msg),
          timestamp: format_date(msg.created_at),
          private: msg.private?,
          content: msg.content.presence,
          call: decorate_call(msg),
          attachments: decorate_attachments(msg.attachments)
        }
      end

      # A chamada chega como mensagem de conteúdo `voice_call`: o texto é só "Chamada do WhatsApp"
      # e o que interessa — duração, sentido, quem falou — mora em content_attributes['data'].
      # Sem isto o histórico registra que houve uma ligação, mas não quanto tempo durou.
      def decorate_call(msg)
        return unless msg.voice_call?

        dados = msg.content_attributes['data'] || {}
        saida = dados['call_direction'].to_s == 'outbound'

        {
          title: saida ? 'Chamada efetuada' : 'Chamada recebida',
          # Quem ligou "efetua"; quem recebeu "atende". Trocar os dois faz o documento descrever
          # errado quem procurou quem.
          agent_label: saida ? 'Efetuada por' : 'Atendida por',
          agent: dados.dig('accepted_by', 'name'),
          status: CALL_STATUS_LABELS[dados['status'].to_s] || dados['status'].presence,
          duration: call_duration_label(dados['duration_seconds'])
        }
      end

      # Segundos crus não se leem num documento: 97 vira "1 min 37 s".
      def call_duration_label(segundos)
        total = segundos.to_i
        return nil if total <= 0
        return "#{total} s" if total < 60

        minutos, resto = total.divmod(60)
        resto.zero? ? "#{minutos} min" : "#{minutos} min #{resto} s"
      end

      # Mesmo link assinado do `download_url`, só que com a validade deste documento em vez dos
      # 5 minutos padrão. Anexo sem arquivo próprio (só URL externa) devolve vazio e o chamador
      # cai no external_url.
      def attachment_url(att)
        return '' unless att.file&.attached?

        ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
        att.file.blob.url(expires_in: ATTACHMENT_LINK_TTL)
      rescue StandardError => e
        Rails.logger.warn "[HtmlExporter] Could not sign attachment #{att.id}: #{e.message}"
        att.download_url
      end

      def decorate_attachments(attachments)
        attachments.map do |att|
          case att.file_type.to_sym
          when :image
            decorate_image_attachment(att)
          when :audio
            { type: :audio, url: attachment_url(att), filename: att.file&.filename.to_s,
              size: human_size(att.file&.byte_size) }
          when :video
            { type: :video, url: attachment_url(att), filename: att.file&.filename.to_s,
              size: human_size(att.file&.byte_size) }
          when :file
            { type: :file, url: attachment_url(att), filename: att.file&.filename.to_s,
              size: human_size(att.file&.byte_size) }
          when :location
            { type: :location, lat: att.coordinates_lat, lng: att.coordinates_long,
              title: att.fallback_title }
          else
            { type: :other, url: attachment_url(att).presence || att.external_url, filename: att.fallback_title }
          end
        end
      end

      # GIFs chegam do WhatsApp classificadas como file_type :image (a API da Meta nao tem um
      # tipo "animated image" separado), mas sao efetivamente um video curto — muitas vezes uma
      # gravacao de tela. Achatar isso pra JPEG estatico pega SEMPRE o primeiro frame
      # (MiniMagick#format usa page: 0 por padrao), que pode nao ter nada a ver com o conteudo
      # real (ex: pegou o instante exato de um toque/circulo desenhado pelo app de gravacao).
      # Tratado como :video (link, nao imagem embutida) — mais fiel que qualquer frame unico.
      def decorate_image_attachment(att)
        if att.file&.content_type == 'image/gif'
          { type: :video, url: attachment_url(att), filename: att.file&.filename.to_s,
            size: human_size(att.file&.byte_size) }
        else
          { type: :image, data_uri: image_to_base64(att), filename: att.file&.filename.to_s }
        end
      end

      # Downloads image, resizes to MAX_IMAGE_WIDTH and converts to JPEG base64.
      # Falls back to the original URL on any error so the PDF is never broken.
      def image_to_base64(attachment)
        raw_url = attachment.download_url.presence || attachment.external_url.presence
        return nil if raw_url.blank?

        Timeout.timeout(EMBED_TIMEOUT) do
          image = MiniMagick::Image.read(URI.open(raw_url, read_timeout: EMBED_TIMEOUT)) # rubocop:disable Security/Open
          compress_image(image)
        end
      rescue StandardError => e
        Rails.logger.warn "[HtmlExporter] Could not embed image (attachment #{attachment.id}): #{e.message}"
        nil
      end

      def compress_image(image)
        # ">" only shrinks images larger than the box (never upscales), fitting within BOTH
        # dimensions while preserving aspect ratio — a tall portrait screenshot gets capped by
        # height here, not just width.
        image.resize("#{MAX_IMAGE_WIDTH}x#{MAX_IMAGE_HEIGHT}>")

        # Flatten transparent layers onto a white background to avoid black background in JPEGs
        image.combine_options do |c|
          c.background 'white'
          c.alpha 'remove'
          c.alpha 'off'
        end

        # Convert to JPEG for consistent compression
        image.format('jpg')
        image.quality(IMAGE_QUALITY.to_s)

        encoded = Base64.strict_encode64(image.to_blob)
        "data:image/jpeg;base64,#{encoded}"
      end

      def human_size(bytes)
        return '' unless bytes

        if bytes >= 1.megabyte
          "#{(bytes.to_f / 1.megabyte).round(1)} MB"
        elsif bytes >= 1.kilobyte
          "#{(bytes.to_f / 1.kilobyte).round(0)} KB"
        else
          "#{bytes} B"
        end
      end
    end
  end
end
