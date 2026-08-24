require 'open-uri'
require 'base64'
require 'mini_magick'

module Conversations
  module Exporter
    class HtmlExporter < BaseExporter
      # Images are resized to this max width before base64 encoding.
      # Keeps file size manageable while preserving legibility.
      MAX_IMAGE_WIDTH  = 800
      IMAGE_QUALITY    = 75   # JPEG quality (1-100); 75 is visually lossless for documents
      EMBED_TIMEOUT    = 8    # seconds per image download

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
          attachments: decorate_attachments(msg.attachments)
        }
      end

      def decorate_attachments(attachments)
        attachments.map do |att|
          case att.file_type.to_sym
          when :image
            decorate_image_attachment(att)
          when :audio
            { type: :audio, url: att.download_url, filename: att.file&.filename.to_s,
              size: human_size(att.file&.byte_size) }
          when :video
            { type: :video, url: att.download_url, filename: att.file&.filename.to_s,
              size: human_size(att.file&.byte_size) }
          when :file
            { type: :file, url: att.download_url, filename: att.file&.filename.to_s,
              size: human_size(att.file&.byte_size) }
          when :location
            { type: :location, lat: att.coordinates_lat, lng: att.coordinates_long,
              title: att.fallback_title }
          else
            { type: :other, url: att.download_url || att.external_url, filename: att.fallback_title }
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
          { type: :video, url: att.download_url, filename: att.file&.filename.to_s,
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
        # Resize only if wider than limit to avoid upscaling
        if image.width > MAX_IMAGE_WIDTH
          image.resize("#{MAX_IMAGE_WIDTH}x")
        end

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
