module User::Accessor
  extend ActiveSupport::Concern

  included do
    has_many :accesses, dependent: :destroy
    has_many :boards, through: :accesses
    has_many :accessible_columns, through: :boards, source: :columns

    after_create_commit :grant_access_to_boards, unless: :system?
  end

  # S2 F.4 (fizzy-eq4.4): Board membership is computed from Beads labels
  # mirrored into MySQL `tags`/`taggings`. Since `Board#cards` is label-based,
  # `User#accessible_cards` cannot be modeled as `has_many :through` via the
  # `boards -> cards` reflection (Rails passes the User as the scope owner,
  # breaking `Board#cards` owner-dependent scopes).
  #
  # Instead, compute accessible cards directly from the user's accessible boards:
  # - `accesses` grants board visibility
  # - a card is a member of a board iff it has the membership label tagging
  def accessible_cards
    @accessible_cards ||= begin
      labels = boards.pluck(:id).map { |id| "#{Board::BOARD_LABEL_PREFIX}#{id}" }
      return Card.none if labels.empty?

      Card
        .joins(taggings: :tag)
        .where(tags: { title: labels })
        .distinct
    end
  end

  def draft_new_card_in(board)
    board.cards.find_or_initialize_by(creator: self, status: "drafted").tap do |card|
      card.update!(created_at: Time.current, updated_at: Time.current, last_active_at: Time.current)
    end
  end

  private
    def grant_access_to_boards
      Access.insert_all account.boards.all_access.ids.collect { |board_id| { id: ActiveRecord::Type::Uuid.generate, board_id: board_id, user_id: id, account_id: account.id } }
    end
end
