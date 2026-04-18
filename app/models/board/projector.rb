class Board::Projector
  # S2 F.6 (fizzy-eq4.6): computed board show substrate for Kanban + List.
  # All relations are MySQL-only and derived from the Card mirror:
  # - board membership via the `fizzy/board/<uuid>` label (Board#cards scope)
  # - column placement via `cards.beads_status` + optional `columns.match_label`
  # - pinned overlay via user pins + Beads status='pinned'
  #
  # NOTE: This does not make controller/view decisions (S2 F.7 / S2 F.11).
  # It provides query building blocks that those rewires can depend on.

  BASE_BEADS_STATUSES = %w[ open in_progress blocked deferred closed pinned ].freeze

  def initialize(board, user: Current.user)
    @board = board
    @user = user
  end

  attr_reader :board, :user

  def board_cards
    board.cards
  end

  def columns
    board.columns.sorted
  end

  # Cards that should be rendered in the pinned overlay for this board.
  # This includes explicit user pins plus Beads status='pinned' issues.
  def pinned_overlay
    pinned_by_user = board_cards.joins(:pins).where(pins: { user_id: user.id })
    pinned_by_status = board_cards.where(beads_status: "pinned")

    board_cards
      .where(id: pinned_by_user.select(:id))
      .or(board_cards.where(id: pinned_by_status.select(:id)))
  end

  # The canonical “list view” set: every board member card, excluding pinned.
  # (Pinned cards are expected to appear via pinned_overlay.)
  def list_cards
    board_cards.where.not(beads_status: "pinned")
  end

  # Cards placed in a specific Kanban column per S2 §B.3 precedence rules.
  # Column must belong to this board.
  def cards_for_column(column)
    raise ArgumentError, "column must belong to board" unless column.board_id == board.id

    scope = list_cards
    scope = apply_status_filter(scope, column.beads_status)

    # Label-driven custom columns: within each beads_status group, columns with
    # match_label take precedence; the catch-all column (match_label nil) must
    # exclude cards that match any label-driven sibling column.
    siblings = board.columns.where(beads_status: column.beads_status).sorted

    if column.match_label.present?
      prior_labels = siblings.take_while { |c| c.id != column.id }.filter_map(&:match_label)
      scope = scope.where(id: cards_matching_any_label(column.match_label))
      scope = scope.where.not(id: cards_matching_any_label(prior_labels)) if prior_labels.any?
    else
      all_match_labels = siblings.filter_map(&:match_label)
      scope = scope.where.not(id: cards_matching_any_label(all_match_labels)) if all_match_labels.any?
    end

    scope
  end

  private
    def apply_status_filter(scope, beads_status)
      status = beads_status.to_s
      return scope if status.blank?

      case status
      when "open"
        open_status_scope(scope)
      when "closed"
        closed_status_scope(scope)
      else
        scope.where(beads_status: status)
      end
    end

    def open_status_scope(scope)
      # Fallback rule (S2 §B.2): unknown/custom statuses remain visible in Todo.
      # If Beads custom statuses are mirrored, exclude custom statuses
      # categorized as done/frozen so they land in Done.
      scope.where(beads_status: nil)
        .or(
          scope
            .where.not(beads_status: BASE_BEADS_STATUSES - [ "open" ])
            .where.not(beads_status: done_or_frozen_custom_status_names)
        )
    end

    def closed_status_scope(scope)
      scope.where(beads_status: "closed")
        .or(scope.where(beads_status: done_or_frozen_custom_status_names))
    end

    def done_or_frozen_custom_status_names
      Beads::CustomStatus
        .where(category: [ Beads::CustomStatus::DONE, Beads::CustomStatus::FROZEN ])
        .select(:name)
    end

    def cards_matching_any_label(label_or_labels)
      labels = Array(label_or_labels).map(&:to_s).map(&:strip).reject(&:blank?)
      return Tagging.none.select(:card_id) if labels.empty?

      Tagging.joins(:tag).where(tags: { title: labels }).select(:card_id)
    end
end

