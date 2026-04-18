module Board::DefaultColumns
  extend ActiveSupport::Concern

  # Per S2 §B.2 default workflow: every new board gets these 5 columns
  # in this position order. Each column maps a Beads issues.status value
  # via the columns.beads_status mirror column added in fizzy-eq4.1.
  #
  # Order matches P4 §C.2 left-to-right Kanban convention:
  #   Todo → Doing → Blocked → Not now → Done
  DEFAULT_COLUMNS = [
    { name: "Todo",     beads_status: "open" },
    { name: "Doing",    beads_status: "in_progress" },
    { name: "Blocked",  beads_status: "blocked" },
    { name: "Not now",  beads_status: "deferred" },
    { name: "Done",     beads_status: "closed" }
  ].freeze

  included do
    after_create_commit :seed_default_columns
  end

  # Idempotent seed — running twice (legacy boards, retries) is a no-op
  # for already-seeded statuses. Returns the columns that were just
  # created (may be empty on a fully-seeded board).
  def seed_default_columns
    existing_statuses = columns.where.not(beads_status: nil).pluck(:beads_status)
    needed = DEFAULT_COLUMNS.reject { |c| existing_statuses.include?(c[:beads_status]) }
    return [] if needed.empty?

    base_position = columns.maximum(:position) || -1
    needed.each_with_index.map do |attrs, i|
      columns.create!(
        name: attrs[:name],
        beads_status: attrs[:beads_status],
        position: base_position + 1 + i
        # color falls back to Column::Colored::DEFAULT_COLOR.value via before_validation
      )
    end
  end
end
