module Beads
  module Mirror
    # S9 §C.5 (fizzy-pmi.7): per-event mirror procedure. After the C.1-C.4
    # procedures land a Beads row + side effects, this turns the canonical
    # Beads `events` row into one or more Fizzy Event rows via the pure
    # Fizzy::Beads::EventMapper, then Event.create!s each so Notifiable
    # (NotifyRecipientsJob) and WebhookDispatchJob fire intentionally.
    #
    # Idempotency comes from the events.beads_event_id unique index (S8 §B.2);
    # RecordNotUnique races are silently swallowed so replays are no-ops.
    #
    # touch_last_active_at stays silent because the caller wraps this in
    # Current.with(beads_mirror: true) (S8 §B.4 mirror-mode guard).
    # Named EventMirror (rather than Event) to avoid shadowing the AR Event
    # class within the Beads::Mirror namespace — sibling Beads::Mirror::CommentEvent
    # references Event without explicit ::, so a sibling Event module would break it.
    module EventMirror
      class << self
        def call(beads_event, account: Current.account, prior_snapshot: nil)
          payloads = Fizzy::Beads::EventMapper.call(beads_event, account: account, prior_snapshot: prior_snapshot)
          payloads.filter_map { |payload| create_event(payload) }
        end

        private

        def create_event(payload)
          card = Card.find_by(id: payload[:eventable_id])
          return nil unless card # orphaned event — nothing to mirror against

          Event.create!(
            action:         payload[:action],
            beads_event_id: payload[:beads_event_id],
            creator:        payload[:creator],
            eventable:      card,
            board:          card.board,
            account:        card.account,
            created_at:     payload[:created_at],
            particulars:    payload[:particulars] || {}
          )
        rescue ActiveRecord::RecordNotUnique
          Event.find_by(beads_event_id: payload[:beads_event_id])
        end
      end
    end
  end
end
