class Column < ApplicationRecord
  include Colored, Positioned

  belongs_to :account, default: -> { board.account }
  belongs_to :board, touch: true

  # S2 F.5 (fizzy-eq4.5): Columns are projection rules, not card owners.
  # Card placement is derived from:
  # - board membership label (S2 F.4)
  # - cards.beads_status (mirrored from Beads)
  # - optional columns.match_label rule (label-driven custom columns)
  #
  # Keep a `#cards` method for legacy controller/view call sites, but do not
  # model it as a `has_many` association (no `cards.column_id` ownership).
  def cards
    scope = board.cards
    scope = scope.where(beads_status: beads_status) if beads_status.present?
    scope = scope.where(id: card_ids_matching_label) if match_label.present?
    scope
  end

  def matches?(card)
    return false if beads_status.present? && card.beads_status.to_s != beads_status.to_s
    return true if match_label.blank?

    card.tags.any? { |t| t.title.to_s == match_label.to_s }
  end

  private
    def card_ids_matching_label
      # Use a subquery so we don't double-join tags/taggings (Board#cards
      # already joins taggings->tag for membership).
      Tagging.joins(:tag).where(tags: { title: match_label.to_s }).select(:card_id)
    end
end
