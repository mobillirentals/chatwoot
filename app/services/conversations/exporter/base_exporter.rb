module Conversations
  module Exporter
    class BaseExporter
      BRASILIA_TZ = 'Brasilia'.freeze

      def initialize(contact:, conversations:, exported_by:, account:)
        @contact = contact
        @conversations = conversations
        @exported_by = exported_by
        @account = account
      end

      def perform
        raise NotImplementedError, "#{self.class} must implement #perform"
      end

      private

      def format_datetime(dt)
        return '' unless dt

        local = dt.in_time_zone(BRASILIA_TZ)
        "#{local.strftime('%d/%m/%Y às %H:%M:%S')} (BRT) / #{dt.utc.strftime('%H:%M:%S')} (UTC)"
      end

      def format_date(dt)
        return '' unless dt

        dt.in_time_zone(BRASILIA_TZ).strftime('%d/%m/%Y %H:%M')
      end

      def sender_name(message)
        sender = message.sender
        return 'Sistema' unless sender

        role = message.incoming? ? 'cliente' : 'agente'
        "#{sender.name} (#{role})"
      end

      def first_response_time(conversation)
        incoming = conversation.messages.incoming.where(private: false).order(:created_at).first
        outgoing = conversation.messages.outgoing.where(private: false).order(:created_at).first
        return nil unless incoming && outgoing

        diff = outgoing.created_at - incoming.created_at
        minutes = (diff / 60).round
        minutes < 60 ? "#{minutes} min" : "#{(minutes / 60.0).round(1)} h"
      end

      def channel_name(conversation)
        conversation.inbox&.name || 'Desconhecido'
      end

      def content_sha256(conversations)
        raw = conversations.flat_map do |conv|
          conv.messages.order(:created_at).map do |msg|
            "#{conv.id}|#{msg.id}|#{msg.created_at.utc.iso8601}|#{msg.content}"
          end
        end.join("\n")

        Digest::SHA256.hexdigest(raw)
      end
    end
  end
end
