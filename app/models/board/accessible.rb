module Board::Accessible
  extend ActiveSupport::Concern

  included do
    has_many :accesses, dependent: :delete_all do
      def revise(granted: [], revoked: [])
        transaction do
          grant_to granted
          revoke_from revoked
        end
      end

      def grant_to(users)
        Access.insert_all Array(users).collect { |user| { id: ActiveRecord::Type::Uuid.generate, board_id: proxy_association.owner.id, user_id: user.id, account_id: proxy_association.owner.account.id } }
      end

      def revoke_from(users)
        destroy_by user: users unless proxy_association.owner.all_access?
      end
    end

    has_many :users, through: :accesses
    has_many :access_only_users, -> { merge(Access.access_only) }, through: :accesses, source: :user

    scope :all_access, -> { where(all_access: true) }

    after_create :grant_access_to_creator
    after_save_commit :grant_access_to_everyone
  end

  def accessed_by(user)
    access_for(user).accessed
  end

  def access_for(user)
    accesses.find_by(user: user)
  end

  def accessible_to?(user)
    access_for(user).present?
  end

  def clean_inaccessible_data_for(user)
    return if accessible_to?(user)

    mentions_for_user(user).destroy_all
    notifications_for_user(user).destroy_all
    watches_for(user).destroy_all
    pins_for(user).destroy_all
  end

  def watchers
    users.active.where(accesses: { involvement: :watching })
  end

  private
    def grant_access_to_creator
      accesses.create(user: creator, involvement: :watching)
    end

    def grant_access_to_everyone
      accesses.grant_to(account.users.active) if all_access_previously_changed?(to: true)
    end

    def mentions_for_user(user)
      # Query handles 2 paths:
      #
      # 1. Mention->Card
      # 2. Mention->Comment->Card
      #
      # In SQLite (test/dev), comments.id is a uuid column stored as BLOB(16)
      # while mentions.source_id is a string column (25-char base36 UUIDv7).
      # SQL joins comparing those won't match. Use a 2-phase lookup instead.
      if Board.connection.adapter_name == "SQLite"
        card_ids = Card.where(board_id: id).pluck(:id)
        mention_ids = user.mentions.where(source_type: "Card", source_id: card_ids).pluck(:id)

        comment_source_ids = user.mentions.where(source_type: "Comment").pluck(:source_id)
        if comment_source_ids.any?
          comment_ids_on_board = Comment.joins(:card).where(id: comment_source_ids, cards: { board_id: id }).pluck(:id)
          mention_ids.concat(user.mentions.where(source_type: "Comment", source_id: comment_ids_on_board).pluck(:id))
        end

        return user.mentions.where(id: mention_ids.uniq)
      end

      adapter = Board.connection.adapter_name.downcase.to_sym
      uuid_type = ActiveRecord::Type.lookup(:uuid, adapter: adapter)
      board_id_binary = uuid_type.serialize(id)

      user.mentions
        .joins("LEFT JOIN cards ON mentions.source_id = cards.id AND mentions.source_type = 'Card'")
        .joins("LEFT JOIN comments ON mentions.source_id = comments.id AND mentions.source_type = 'Comment'")
        .joins("LEFT JOIN cards AS comment_cards ON comments.card_id = comment_cards.id")
        .where("(mentions.source_type = 'Card' AND cards.board_id = ?) OR (mentions.source_type = 'Comment' AND comment_cards.board_id = ?)", board_id_binary, board_id_binary)
    end

    def notifications_for_user(user)
      # For access cleanup we don't need to join through Event->(Card|Comment) to
      # infer the board. notifications.card_id is the canonical denormalized
      # reference and is always populated.
      user.notifications.where(card_id: cards.select(:id))
    end

    def watches_for(user)
      Watch.where(card: cards, user: user)
    end

    def pins_for(user)
      Pin.where(card: cards, user: user)
    end
end
