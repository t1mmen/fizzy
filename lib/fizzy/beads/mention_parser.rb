module Fizzy
  module Beads
    # Per S6 §F: parses plaintext for mention tokens (@email or @handle).
    # Used by the Mentions concern to derive mention rows from Beads-canonical
    # content (supports CLI-authored comments).
    class MentionParser
      # Matches @ followed by an email address OR a simple word handle.
      # Email form: @user@example.com (primary)
      # Handle form: @alice (best-effort)
      MENTION_REGEX = /@([\w.+\-]+@[\w.+\-]+\.[a-z]{2,}|[\w\-]+)/i

      def self.call(text, mentionable_users:)
        new(text, mentionable_users:).mentionees
      end

      def initialize(text, mentionable_users:)
        @text = text.to_s
        @mentionable_users = mentionable_users.to_a
      end

      def mentionees
        tokens.flat_map { |token| resolve_token(token) }.compact.uniq
      end

      private

      def tokens
        @text.scan(MENTION_REGEX).flatten
      end

      def resolve_token(token)
        if token.include?("@")
          # Primary form: email
          email = token.downcase
          @mentionable_users.select { |u| u.identity.email_address.downcase == email }
        else
          # Handle form: best-effort match against mentionable_handles
          handle = token.downcase
          @mentionable_users.select { |u| u.mentionable_handles.include?(handle) }
        end
      end
    end
  end
end
