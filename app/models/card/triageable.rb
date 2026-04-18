module Card::Triageable
  extend ActiveSupport::Concern

  included do
    belongs_to :column, optional: true, touch: true

    # Post-S4: column placement is status-driven (S2). "Awaiting triage"
    # is the open/Todo status (nil treated as open for transitional AR-created
    # cards that don't come from Beads yet).
    scope :awaiting_triage, -> { active.where(beads_status: [ nil, "open" ]) }
    scope :triaged, -> { active.where.not(beads_status: [ nil, "open" ]) }
  end

  def triaged?
    active? && !awaiting_triage?
  end

  def awaiting_triage?
    active? && beads_status.to_s.in?([ "", "open" ])
  end

  def triage_into(column)
    raise "The column must belong to the card board" unless board == column.board

    transaction do
      resume
      raise ArgumentError, "Column is missing beads_status" if column.beads_status.blank?

      Fizzy::Beads::CommandClient.current.update_status(id, column.beads_status)
      update_columns(beads_status: column.beads_status.to_s, updated_at: Time.current)
    end
  end

  def send_back_to_triage(skip_event: false)
    transaction do
      resume
      Fizzy::Beads::CommandClient.current.update_status(id, "open")
      update_columns(beads_status: "open", updated_at: Time.current)
    end
  end

  # Transitional column projection: until S2 column routing fully lands,
  # treat the column implied by beads_status as the display column.
  def projected_column
    return nil if awaiting_triage?
    return nil if beads_status.blank?
    return nil if beads_status.to_s == "closed"

    board.columns.detect { |c| c.beads_status.to_s == beads_status.to_s }
  end
end
