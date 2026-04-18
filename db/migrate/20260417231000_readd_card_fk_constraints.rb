class ReaddCardFkConstraints < ActiveRecord::Migration[8.0]
  # Per S1 §F.21 (fizzy-i2m): re-add the FK constraints to cards that were
  # dropped by fizzy-x2i (DropCardFkConstraints) before the widening
  # cascade. Now that cards.id is varchar(255) and all child card_id
  # columns are also varchar(255), the FK references are type-compatible.
  #
  # Mirrors x2i's CARD_FK_TABLES list. SQLite is a no-op via guards;
  # MySQL/SAAS production gets the actual constraints back.

  CARD_FK_TABLES = %w[
    assignments
    closures
    taggings
    comments
    steps
    pins
    watches
    notifications
  ].freeze

  def up
    CARD_FK_TABLES.each do |table|
      next unless table_exists?(table)
      next if foreign_key_exists?(table, :cards)
      add_foreign_key table, :cards
    end
  end

  def down
    # Mirror of x2i#up — drop FK constraints again.
    CARD_FK_TABLES.each do |table|
      next unless table_exists?(table)
      next unless foreign_key_exists?(table, :cards)
      remove_foreign_key table, :cards
    end
  end
end
