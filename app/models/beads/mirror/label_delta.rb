module Beads
  module Mirror
    # Per S9 §C.3 (fizzy-pmi.5) + S5 §B.3: callback-bypass label delta
    # procedure. Takes a label add/remove event from Beads (label_added /
    # label_removed) and applies it to the Fizzy MySQL mirror via direct
    # SQL upsert_all / delete_all — no AR callbacks fire.
    #
    # Tags: upserted by (account_id, title) per the unique index. Title
    # is normalized via LabelNormalizer (downcase + strip + reject leading-#).
    # Beads-only invalid labels (e.g. "#Backend" written via bd CLI direct)
    # are silently skipped per S5 §E.4 CLI-only stance.
    #
    # Taggings: upserted by (card_id, tag_id) on add, deleted on remove.
    module LabelDelta
      ADDED   = "added".freeze
      REMOVED = "removed".freeze

      class << self
        def apply(operation:, account_id:, card_id:, label:)
          normalized = normalize(label)
          return if normalized.blank?

          case operation.to_s
          when ADDED   then add(account_id: account_id, card_id: card_id, label: normalized)
          when REMOVED then remove(account_id: account_id, card_id: card_id, label: normalized)
          else
            Rails.logger.warn "[LabelDelta] unknown operation=#{operation.inspect}"
          end
        end

        private

        # Returns nil for invalid labels (S5 §E.4) instead of raising — the
        # poller silently skips and logs.
        def normalize(label)
          Fizzy::Beads::LabelNormalizer.call(label)
        rescue Fizzy::Beads::LabelNormalizer::InvalidLabelError => e
          Rails.logger.info "[LabelDelta] skipping invalid label #{label.inspect}: #{e.message}"
          nil
        end

        def add(account_id:, card_id:, label:)
          now = Time.current
          # Tag.id is uuid NOT NULL (UuidPrimaryKeyDefault initializer only
          # auto-generates on AR create, NOT on upsert_all). Provide an id
          # for the INSERT path; the unique index on (account_id, title)
          # makes the upsert idempotent — the existing row's id is preserved
          # on conflict.
          Tag.upsert_all(
            [ {
              id: ActiveRecord::Type::Uuid.generate,
              account_id: account_id,
              title: label,
              created_at: now,
              updated_at: now
            } ],
            unique_by: [ :account_id, :title ]
          )
          tag = Tag.find_by(account_id: account_id, title: label)
          return unless tag

          Tagging.upsert_all(
            [ {
              id: ActiveRecord::Type::Uuid.generate,
              account_id: account_id,
              card_id: card_id.to_s,
              tag_id: tag.id,
              created_at: now,
              updated_at: now
            } ],
            unique_by: [ :card_id, :tag_id ]
          )
        end

        def remove(account_id:, card_id:, label:)
          tag = Tag.find_by(account_id: account_id, title: label)
          return unless tag

          Tagging.where(card_id: card_id.to_s, tag_id: tag.id).delete_all
          # Tag itself stays (account-wide; may be reused) per S9 §C.3.
        end
      end
    end
  end
end
