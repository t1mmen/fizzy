module Beads
  module Mirror
    # Per S9 §C.4 (fizzy-pmi.6): the per-comment mirror procedure.
    # Takes a Beads-comment-shaped object (Hash, Struct, or AR instance)
    # and upserts a Comment mirror row + ActionText cache + Search::Record
    # + watch derivation + Mention::CreateJob enqueue.
    #
    # Callback-bypass per P9 §A.2 + S5 §B.3: uses Comment.upsert_all keyed on
    # primary id (Beads UUID string), and explicitly triggers side effects.
    #
    # Should be called inside the BeadsPoller's Current.beads_mirror = true
    # context (S8 §B.4 / fizzy-n3l.5 mirror-mode guard).
    module CommentMirror
      class << self
        def call(beads_comment, account_id:)
          row = build_row(beads_comment, account_id: account_id)
          return if row[:id].blank? || row[:card_id].blank?

          # 1. Upsert Comment row
          Comment.upsert_all([ row ], unique_by: :id)
          comment = Comment.find(row[:id])

          # 2. Upsert ActionText cache (Fizzy UI needs HTML derived from Beads plaintext)
          sync_action_text_cache(comment, beads_comment)

          # 3. Explicitly sync Search::Record
          sync_search_record(comment, beads_comment)

          # 4. Derive watch for comment creator
          ensure_watch_for_creator(comment)

          # 5. Enqueue Mention::CreateJob
          enqueue_mention_derivation(comment)

          comment
        end

        private

        def build_row(beads_comment, account_id:)
          created_at = read(beads_comment, :created_at)
          creator = resolve_creator(beads_comment, account_id: account_id)

          {
            id:          read(beads_comment, :id).to_s,
            card_id:     read(beads_comment, :issue_id).to_s,
            account_id:  account_id,
            creator_id:  creator&.id,
            created_at:  created_at,
            updated_at:  created_at
          }.compact
        end

        def resolve_creator(beads_comment, account_id:)
          author = read(beads_comment, :author)
          account = Account.find(account_id)
          Fizzy::Beads::ActorMapper.resolve(author, account: account)
        rescue ActiveRecord::RecordNotFound => e
          Rails.logger.warn "[CommentMirror] creator resolution failed: #{e.message}"
          nil
        end

        def sync_action_text_cache(comment, beads_comment)
          plaintext = read(beads_comment, :text)
          html = Fizzy::Beads::PlaintextToActionTextHtml.call(plaintext)

          # Per P9 §A.2: upsert_all bypasses callbacks. In SQLite, we must provide
          # the id PK explicitly for upsert_all to succeed.
          ActionText::RichText.upsert_all([
            {
              id:          ActiveRecord::Type::Uuid.generate,
              account_id:  comment.account_id,
              record_type: "Comment",
              record_id:   comment.id,
              name:        "body",
              body:        html,
              created_at:  comment.created_at,
              updated_at:  comment.created_at
            }
          ], unique_by: [ :record_type, :record_id, :name ])
        end

        def sync_search_record(comment, beads_comment)
          plaintext = read(beads_comment, :text)
          content = plaintext.to_s.truncate(10000)

          Search::Record.upsert!(
            account_id:      comment.account_id,
            searchable_type: "Comment",
            searchable_id:   comment.id,
            card_id:         comment.card_id,
            board_id:        comment.card.board_id,
            title:           "",
            content:         content,
            created_at:      comment.created_at
          )
        rescue => e
          Rails.logger.warn "[CommentMirror] Search::Record sync failed for comment=#{comment.id}: #{e.class}: #{e.message}"
        end

        def ensure_watch_for_creator(comment)
          return unless comment.creator_id

          # Per S9 §C.4: ensure card is watched by creator.
          # NOTE: Watch table lacks a unique index on [user_id, card_id] in
          # upstream schema, preventing safe use of insert_all(unique_by:).
          # Since poller is single-threaded, check-and-create is safe enough.
          unless Watch.exists?(card_id: comment.card_id, user_id: comment.creator_id)
            Watch.create!(
              account_id: comment.account_id,
              card_id:    comment.card_id,
              user_id:    comment.creator_id,
              watching:   true
            )
          end
        rescue => e
          Rails.logger.warn "[CommentMirror] watch derivation failed for comment=#{comment.id}: #{e.class}: #{e.message}"
        end

        def enqueue_mention_derivation(comment)
          Mention::CreateJob.perform_later(comment.id, creator_id: comment.creator_id)
        rescue => e
          Rails.logger.warn "[CommentMirror] Mention::CreateJob enqueue failed for comment=#{comment.id}: #{e.class}: #{e.message}"
        end

        def read(beads_comment, attr)
          case beads_comment
          when Hash
            beads_comment[attr] || beads_comment[attr.to_s]
          else
            beads_comment.public_send(attr) if beads_comment.respond_to?(attr)
          end
        end
      end
    end
  end
end
