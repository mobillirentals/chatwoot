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

      def first_incoming_message(conversation)
        conversation.messages.incoming.where(private: false).order(:created_at).first
      end

      # Primeira resposta do robô: cliente → 1ª mensagem de saída do agent_bot.
      def bot_first_response_time(conversation)
        bot_reply = conversation.messages.outgoing.where(private: false, sender_type: 'AgentBot')
                                .order(:created_at).first
        response_time_label(first_incoming_message(conversation), bot_reply)
      end

      # Primeira resposta do agente humano: cliente → 1ª mensagem de saída de um User.
      def agent_first_response_time(conversation)
        agent_reply = conversation.messages.outgoing.where(private: false, sender_type: 'User')
                                  .order(:created_at).first
        response_time_label(first_incoming_message(conversation), agent_reply)
      end

      def response_time_label(from_message, to_message)
        return nil unless from_message && to_message

        diff = to_message.created_at - from_message.created_at
        return nil if diff.negative?

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
