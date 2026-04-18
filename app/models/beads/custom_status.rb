module Beads
  # Per S9 §C.2: MySQL mirror of Beads issues.custom_statuses(name, category).
  # Keeps S2 board projector (column routing for custom statuses with
  # category=done|frozen|unspecified per P4 §C.1) MySQL-only — no
  # request-time Beads SQL.
  class CustomStatus < ApplicationRecord
    self.table_name = "beads_custom_statuses"
    self.primary_key = "name"

    DONE        = "done".freeze
    FROZEN      = "frozen".freeze
    UNSPECIFIED = "unspecified".freeze
    KNOWN_CATEGORIES = [ DONE, FROZEN, UNSPECIFIED ].freeze

    validates :name, presence: true, length: { maximum: 64 }
    validates :category, presence: true, length: { maximum: 32 }

    scope :by_category, ->(category) { where(category: category.to_s) }
    scope :done,        -> { by_category(DONE) }
    scope :frozen_state, -> { by_category(FROZEN) }
    scope :unspecified, -> { by_category(UNSPECIFIED) }

    # Used by BeadsResync (fizzy-pmi.8) to refresh the mirror wholesale
    # from the canonical Beads custom_statuses table. Caller passes an
    # array of {name:, category:} hashes (or any duck-typed equivalent).
    def self.refresh_from(beads_rows)
      now = Time.current
      rows = beads_rows.map do |r|
        {
          name: r.respond_to?(:name) ? r.name : r[:name] || r["name"],
          category: r.respond_to?(:category) ? r.category : r[:category] || r["category"],
          updated_at: now
        }
      end
      upsert_all(rows, unique_by: :name) unless rows.empty?
    end
  end
end
