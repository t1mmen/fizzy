module Beads
  module Mirror
    # Per S9 §A.2: per-source highwater cursor for the BeadsPoller engine.
    # Stored in MySQL as the canonical source-of-truth for "what have we
    # already processed from Beads?".
    #
    # processed_ids is a JSON array of Beads ids that share the same
    # created_at as last_seen_at — used to dedupe within the overlap window.
    # On tick advance: replace processed_ids wholesale with ids of rows whose
    # created_at == new last_seen_at (S9 §A.2 step 2 v1.1).
    class Cursor < ApplicationRecord
      self.table_name = "beads_mirror_cursors"
      self.primary_key = "source"

      OVERLAP_SECONDS = 2

      EVENTS = "events".freeze
      COMMENTS = "comments".freeze
      ISSUES_SNAPSHOT = "issues_snapshot".freeze

      validates :source, presence: true, inclusion: { in: [ EVENTS, COMMENTS, ISSUES_SNAPSHOT ] }

      def processed_id_set
        return [] if processed_ids.blank?
        JSON.parse(processed_ids)
      rescue JSON::ParserError
        []
      end

      def advance!(new_last_seen_at:, new_processed_ids:)
        update!(
          last_seen_at: new_last_seen_at,
          processed_ids: JSON.dump(Array(new_processed_ids)),
          last_advanced_at: Time.current
        )
      end

      def self.for(source)
        find_or_create_by!(source: source)
      end
    end
  end
end
