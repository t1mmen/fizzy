module Board::Cards
  extend ActiveSupport::Concern

  included do
    # S2 F.4 (fizzy-eq4.4): Board membership is projected via Beads labels
    # mirrored into MySQL `tags`/`taggings`. Board#cards must be label-based
    # (not `cards.board_id`) so we never need cross-DB joins.
    #
    # NOTE: this remains a `has_many` to preserve legacy builder APIs
    # (`board.cards.create!` in fixtures/tests). The scope defines membership.
    has_many :cards, ->(board) {
      joins(taggings: :tag)
        .where(tags: { title: board.membership_label })
        .distinct
    }

    after_update_commit -> { cards.touch_all }, if: :saved_change_to_name?
  end
end
