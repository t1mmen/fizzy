module Beads
  module Mirror
    # Per S9 §C.1 (fizzy-pmi.3): the per-issue mirror procedure. Takes a
    # Beads-issue-shaped object (Hash, Struct, or AR instance — duck-typed
    # over .id / .status / .closed_at / .defer_until / .close_reason / .title)
    # and upserts a Card mirror row + explicit Search::Record sync.
    #
    # Callback-bypass per P9 §A.2 + S5 §B.3: uses Card.upsert_all keyed on
    # primary id (idempotent on re-tick), and explicitly triggers
    # Search::Record sync since AR after_save_commit on Card is bypassed.
    #
    # Should be called inside the BeadsPoller's Current.beads_mirror = true
    # context (S8 §B.4 / fizzy-n3l.5 mirror-mode guard) so any side-effects
    # that DO fall through (e.g. Card#touch_last_active_at) bypass cascading
    # callbacks.
    module IssueMirror
      MIRRORED_FIELDS = %i[ id beads_status closed_at defer_until close_reason title beads_metadata ].freeze

      class << self
        def call(beads_issue, account_id:, board_id:, creator_id: nil)
          row = build_row(beads_issue, creator_id: creator_id)
          return if row[:id].blank?

          Card.upsert_all([ row.merge(account_id: account_id, board_id: board_id) ], unique_by: :id)
          card = Card.find(row[:id])
          sync_search_record(card)
          card
        end

        private

        def build_row(beads_issue, creator_id:)
          now = Time.current
          # Cards table is NOT NULL on created_at/creator_id — supply
          # sensible defaults so upsert_all succeeds on first-mirror.
          # Subsequent mirrors are upserts and don't change these columns.
          {
            id:             read(beads_issue, :id).to_s,
            beads_status:   read(beads_issue, :status),
            closed_at:      read(beads_issue, :closed_at),
            defer_until:    read(beads_issue, :defer_until),
            close_reason:   read(beads_issue, :close_reason),
            title:          read(beads_issue, :title) || "(untitled)",
            beads_metadata: extract_metadata(beads_issue),
            creator_id:     creator_id || resolve_default_creator_id,
            number:         next_card_number(read(beads_issue, :id)),
            last_active_at: now,
            created_at:     now,
            updated_at:     now
          }.compact
        end

        # Per S9 §C.1 + S3 §F (SystemActor): when no caller-provided creator
        # is given, default to the SystemActor's User row. Returns nil if
        # the system user hasn't been bootstrapped (callers must then
        # pass creator_id explicitly).
        def resolve_default_creator_id
          SystemActor.user&.id
        rescue ActiveRecord::RecordNotFound
          nil
        end

        # Cards.number is a per-account sequence (legacy Fizzy ergonomic
        # for human-readable URLs) — NOT NULL. For mirrored cards: preserve
        # existing number if the card exists; otherwise generate the next
        # value. (When the controllers switch routes to cards/:id varchar
        # Beads id post-S6, this can simplify.)
        def next_card_number(card_id)
          existing = Card.where(id: card_id).pick(:number)
          return existing if existing
          (Card.maximum(:number) || 0) + 1
        end

        # Per S10 §E.1 + fizzy-e5m.1 REPLACE semantics: mirror the entire
        # metadata.fizzy bucket from Beads into cards.beads_metadata each tick.
        def extract_metadata(beads_issue)
          metadata = read(beads_issue, :metadata)
          return nil unless metadata.is_a?(Hash)
          fizzy_bucket = metadata["fizzy"] || metadata[:fizzy]
          fizzy_bucket.is_a?(Hash) ? fizzy_bucket : nil
        end

        # Duck-typed reader: works for Hash (with string OR symbol keys),
        # Struct, and AR instances.
        def read(beads_issue, attr)
          case beads_issue
          when Hash
            beads_issue[attr] || beads_issue[attr.to_s]
          else
            beads_issue.public_send(attr) if beads_issue.respond_to?(attr)
          end
        end

        # Search::Record sync for the mirrored Card. Per S9 §B.2: poller
        # must explicitly invoke side effects that callback-bypass writes
        # would normally trigger.
        def sync_search_record(card)
          Search::Record.upsert!(
            account_id: card.account_id,
            searchable_type: "Card",
            searchable_id: card.id,
            card_id: card.id,
            board_id: card.board_id,
            title: card.title.to_s,
            content: [ card.title, card.beads_status ].compact.join(" "),
            created_at: card.created_at || Time.current
          )
        rescue ActiveRecord::ActiveRecordError => e
          Rails.logger.warn "[IssueMirror] Search::Record.upsert! failed for card=#{card.id}: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
