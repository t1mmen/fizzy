class Board < ApplicationRecord
  # Reserved Beads label prefix for board membership (S2 §A.2 + S5 §D.1).
  # System labels under "fizzy/board/<board_uuid>" are written by board
  # create/move flows and projected into Card mirror via the S9 poller.
  BOARD_LABEL_PREFIX = "fizzy/board/".freeze

  include Accessible, AutoPostponing, Board::Storage, Broadcastable, Cards, Entropic, Filterable, Publishable, ::Storage::Tracked, Triageable

  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :account, default: -> { creator.account }

  has_rich_text :public_description

  has_many :tags, -> { distinct }, through: :cards
  has_many :events
  has_many :webhooks, dependent: :destroy

  scope :alphabetically, -> { order("lower(name)") }
  scope :ordered_by_recently_accessed, -> { merge(Access.ordered_by_recently_accessed) }

  # Canonical Beads label string for this board's membership.
  # Per S2 §A.2: stable across renames, collision-safe via reserved fizzy/ prefix.
  def membership_label
    "#{BOARD_LABEL_PREFIX}#{id}"
  end

  # True if `label` is any board-membership label (system-owned).
  def self.board_label?(label)
    label.to_s.start_with?(BOARD_LABEL_PREFIX)
  end
end
