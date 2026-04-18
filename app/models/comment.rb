class Comment < ApplicationRecord
  include Attachments, Eventable, Mentions, Promptable, Searchable, Storage::Tracked

  belongs_to :account, default: -> { card.account }
  belongs_to :card, touch: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }
  has_many :reactions, -> { order(:created_at) }, as: :reactable, dependent: :delete_all

  has_rich_text :body

  validate :card_is_commentable

  # Post-edq.1 widening (S6 F.1): comments.id is now varchar(255), so the
  # UuidPrimaryKeyDefault initializer no longer auto-generates UUIDs (it
  # only fires on :uuid columns). Explicit before_create generates a UUID
  # for AR-created comments (system_commenter, controllers, fixtures);
  # poller-mirrored comments carry the Beads comment id and skip this
  # default. Same pattern as Card mirror (see app/models/card.rb).
  before_create -> { self.id ||= ActiveRecord::Type::Uuid.generate }

  scope :chronologically, -> { order created_at: :asc, id: :desc }
  scope :preloaded, -> { with_rich_text_body.includes(reactions: :reacter) }
  scope :by_system, -> { joins(:creator).where(creator: { role: :system }) }
  scope :by_user, -> { joins(:creator).where.not(creator: { role: :system }) }

  after_create_commit :watch_card_by_creator

  delegate :publicly_accessible?, :accessible_to?, :board, :watch_by, to: :card

  def to_partial_path
    "cards/#{super}"
  end

  private
    def card_is_commentable
      errors.add(:card, "does not allow comments") unless card.commentable?
    end

    def watch_card_by_creator
      card.watch_by creator
    end
end
