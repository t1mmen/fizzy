module Fizzy
  module Beads
    # S8 F.3 (fizzy-n3l.3): pure mapping from a canonical Beads events row
    # into one (or more) Fizzy Event creation payloads.
    #
    # The caller (S9 poller / mirror procedure) is responsible for:
    # - selecting which Beads rows to process
    # - resolving board-at-time-of-event if needed
    # - actually creating Event rows (and handling RecordNotUnique dedup)
    #
    # This mapper ONLY translates "what happened" into Fizzy's
    # ActivitiesController::ACTIONS action set and particulars shapes.
    class EventMapper
      BOARD_LABEL_PREFIX = Board::BOARD_LABEL_PREFIX

      class << self
        def call(beads_event, account: Current.account, prior_snapshot: nil)
          return [] if beads_event.blank?

          id = read(beads_event, :id).to_s
          issue_id = read(beads_event, :issue_id).to_s
          created_at = read(beads_event, :created_at) || Time.current

          event_type = read(beads_event, :event_type).to_s
          actor = read(beads_event, :actor)
          creator = ActorMapper.resolve(actor, account: account)

          case event_type
          when "created"
            [ payload(action: "card_published", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: {}) ]
          when "closed"
            [ payload(action: "card_closed", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: {}) ]
          when "updated"
            map_updated_event(id, beads_event, creator:, account:, issue_id:, created_at:, prior_snapshot:)
          else
            []
          end
        end

        private

        def map_updated_event(id, beads_event, creator:, account:, issue_id:, created_at:, prior_snapshot:)
          old_snapshot = parse_snapshot(read(beads_event, :old_value)) || parse_snapshot(prior_snapshot) || {}
          new_snapshot = parse_snapshot(read(beads_event, :new_value)) || {}

          mappings = []

          mappings.concat(map_status_change(id, creator:, issue_id:, created_at:, old_snapshot:, new_snapshot:))
          mappings.concat(map_defer_until(id, creator:, issue_id:, created_at:, old_snapshot:, new_snapshot:))
          mappings.concat(map_title_change(id, creator:, issue_id:, created_at:, old_snapshot:, new_snapshot:))
          mappings.concat(map_assignee_change(id, creator:, account:, issue_id:, created_at:, old_snapshot:, new_snapshot:))
          mappings.concat(map_board_change(id, creator:, account:, issue_id:, created_at:, old_snapshot:, new_snapshot:))
          mappings.concat(map_triage_change(id, creator:, issue_id:, created_at:, old_snapshot:, new_snapshot:))

          mappings
        end

        def map_status_change(id, creator:, issue_id:, created_at:, old_snapshot:, new_snapshot:)
          old_status = old_snapshot["status"].to_s
          new_status = new_snapshot["status"].to_s
          return [] if old_status == new_status

          if new_status == "closed" && old_status != "closed"
            [ payload(action: "card_closed", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: {}) ]
          elsif old_status == "closed" && new_status != "closed"
            [ payload(action: "card_reopened", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: {}) ]
          else
            []
          end
        end

        def map_defer_until(id, creator:, issue_id:, created_at:, old_snapshot:, new_snapshot:)
          old_until = old_snapshot["defer_until"]
          new_until = new_snapshot["defer_until"]
          return [] unless old_until.blank? && new_until.present?

          action = creator.system? ? "card_auto_postponed" : "card_postponed"
          [ payload(action:, beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: {}) ]
        end

        def map_title_change(id, creator:, issue_id:, created_at:, old_snapshot:, new_snapshot:)
          old_title = old_snapshot["title"].to_s
          new_title = new_snapshot["title"].to_s
          return [] if old_title == new_title || old_title.blank? || new_title.blank?

          particulars = { "particulars" => { "old_title" => old_title, "new_title" => new_title } }
          [ payload(action: "card_title_changed", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: particulars) ]
        end

        def map_assignee_change(id, creator:, account:, issue_id:, created_at:, old_snapshot:, new_snapshot:)
          old_assignee = old_snapshot["assignee"]
          new_assignee = new_snapshot["assignee"]
          return [] if old_assignee.to_s == new_assignee.to_s

          old_user = resolve_user(old_assignee, account)
          new_user = resolve_user(new_assignee, account)

          # nil -> value
          if old_user.nil? && new_user
            return [ payload(action: "card_assigned", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: { "assignee_ids" => [ new_user.id ] }) ]
          end

          # value -> nil
          if old_user && new_user.nil?
            return [ payload(action: "card_unassigned", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: { "assignee_ids" => [ old_user.id ] }) ]
          end

          # value(A) -> value(B) : emit unassign then assign
          if old_user && new_user && old_user != new_user
            return [
              payload(action: "card_unassigned", beads_event_id: beads_event_id(id, suffix: "unassign"), creator:, issue_id:, created_at:, particulars: { "assignee_ids" => [ old_user.id ] }),
              payload(action: "card_assigned", beads_event_id: beads_event_id(id, suffix: "assign"), creator:, issue_id:, created_at:, particulars: { "assignee_ids" => [ new_user.id ] })
            ]
          end

          []
        end

        def map_board_change(id, creator:, account:, issue_id:, created_at:, old_snapshot:, new_snapshot:)
          old_labels = Array(old_snapshot["labels"])
          new_labels = Array(new_snapshot["labels"])

          old_board_label = old_labels.find { |l| l.to_s.start_with?(BOARD_LABEL_PREFIX) }
          new_board_label = new_labels.find { |l| l.to_s.start_with?(BOARD_LABEL_PREFIX) }
          return [] if old_board_label.to_s == new_board_label.to_s

          old_board = board_name_from_label(old_board_label, account)
          new_board = board_name_from_label(new_board_label, account)
          particulars = { "particulars" => { "old_board" => old_board.to_s, "new_board" => new_board.to_s } }

          [ payload(action: "card_board_changed", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: particulars) ]
        end

        def map_triage_change(id, creator:, issue_id:, created_at:, old_snapshot:, new_snapshot:)
          old_status = old_snapshot["status"].to_s
          new_status = new_snapshot["status"].to_s
          return [] if old_status == new_status

          # Closed/reopened are separate actions; do not double-emit "triage".
          return [] if old_status == "closed" || new_status == "closed"

          # Best-effort mapping to match legacy "triage" language:
          # - open -> non-open means the card moved into a workflow column
          # - non-open -> open means it went back to triage/inbox
          if old_status == "open" && new_status.present? && new_status != "open"
            column = default_column_label_for(new_status)
            particulars = { "particulars" => { "column" => column } }
            return [ payload(action: "card_triaged", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: particulars) ]
          end

          if old_status.present? && old_status != "open" && new_status == "open"
            return [ payload(action: "card_sent_back_to_triage", beads_event_id: beads_event_id(id), creator:, issue_id:, created_at:, particulars: {}) ]
          end

          []
        end

        def default_column_label_for(beads_status)
          case beads_status.to_s
          when "open" then "Todo"
          when "in_progress" then "Doing"
          when "blocked" then "Blocked"
          when "deferred" then "Not now"
          when "closed" then "Done"
          else "Todo"
          end
        end

        def board_name_from_label(label, account)
          return "" if label.blank?

          id = label.to_s.delete_prefix(BOARD_LABEL_PREFIX)
          Board.find_by(id: id, account_id: account.id)&.name || id
        end

        def resolve_user(value, account)
          string = value.to_s.strip
          return nil if string.blank? || string == "null"
          ActorMapper.resolve(string, account: account)
        rescue => _e
          nil
        end

        def beads_event_id(beads_event_id, suffix: nil)
          base = "event:#{beads_event_id}"
          suffix.present? ? "#{base}:#{suffix}" : base
        end

        def payload(action:, beads_event_id:, creator:, issue_id:, created_at:, particulars:)
          {
            action: action,
            beads_event_id: beads_event_id,
            creator: creator,
            eventable_type: "Card",
            eventable_id: issue_id,
            created_at: created_at,
            particulars: particulars
          }
        end

        def parse_snapshot(value)
          return value if value.is_a?(Hash)
          return nil if value.blank?

          JSON.parse(value.to_s)
        rescue JSON::ParserError
          nil
        end

        def read(beads_event, attr)
          case beads_event
          when Hash
            beads_event[attr] || beads_event[attr.to_s]
          else
            beads_event.public_send(attr) if beads_event.respond_to?(attr)
          end
        end
      end
    end
  end
end
