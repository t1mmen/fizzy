module Card::Closeable
  extend ActiveSupport::Concern

  included do
    has_one :closure, dependent: :destroy

    scope :closed, -> {
      left_outer_joins(:closure)
        .where("cards.beads_status = ? OR closures.id IS NOT NULL", "closed")
    }
    scope :open, -> {
      left_outer_joins(:closure)
        .where("cards.beads_status IS NULL OR cards.beads_status != ?", "closed")
        .where(closures: { id: nil })
    }

    scope :recently_closed_first, -> { closed.order(closed_at: :desc) }
    scope :closed_at_window, ->(window) {
      closed.where("COALESCE(cards.closed_at, closures.created_at) BETWEEN ? AND ?", window.begin, window.end)
    }
    scope :closed_by, ->(users) { joins(:closure).where(closures: { user_id: Array(users) }) }
  end

  def closed?
    beads_status.to_s == "closed" || closure.present?
  end

  def open?
    !closed?
  end

  def closed_by
    closure&.user
  end

  def closed_at
    self[:closed_at] || closure&.created_at
  end

  def close(user: Current.user)
    unless closed?
      transaction do
        not_now&.destroy
        create_closure! user: user
        track_event :closed, creator: user
      end
    end
  end

  def reopen(user: Current.user)
    if closed?
      transaction do
        closure&.destroy
        track_event :reopened, creator: user
      end
    end
  end
end
