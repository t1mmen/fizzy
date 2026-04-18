module Beads
  module Mirror
    # S8 §A.4 + §F.1 (fizzy-n3l.4): after the S6 comment mirror upserts a
    # Comment row, mirror it as a comment_created Event so the activity feed
    # / Notifier fanout / webhook dispatch fire even for CLI-originated
    # comments. Dedup via events.beads_event_id (unique index from n3l.1).
    module CommentEvent
      def self.call(comment)
        beads_event_id = key_for(comment)

        Event.find_or_create_by!(beads_event_id: beads_event_id) do |event|
          event.action      = "comment_created"
          event.creator     = comment.creator
          event.eventable   = comment
          event.board       = comment.card.board
          event.account     = comment.card.account
          event.particulars = {}
          event.created_at  = comment.created_at
        end
      rescue ActiveRecord::RecordNotUnique
        Event.find_by!(beads_event_id: beads_event_id)
      end

      def self.key_for(comment)
        "comment:#{comment.id}"
      end
    end
  end
end
