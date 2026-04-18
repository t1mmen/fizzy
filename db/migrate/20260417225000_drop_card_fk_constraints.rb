class DropCardFkConstraints < ActiveRecord::Migration[8.0]
  # Per S1 §B.7 (fizzy-x2i): drop FK constraints from child tables that
  # reference cards.id BEFORE widening the cards.id PK from uuid to
  # varchar(255). MySQL refuses type changes that violate referential
  # integrity, so the FKs must come off first; F.21 (fizzy-i2m) re-adds
  # them with the new varchar types.
  #
  # SQLite does not enforce DB-level FKs the same way; in dev (sqlite)
  # most of these are no-ops because no constraint exists. Guards prevent
  # errors either way.
  #
  # Polymorphic columns (action_text_rich_texts.record_id, mentions.source_id,
  # reactions.reactable_id, notifications.source_id, active_storage_attachments
  # .record_id, storage_entries.recordable_id) have no DB-level FK and
  # are skipped here entirely.

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
      next unless foreign_key_exists?(table, :cards)
      remove_foreign_key table, :cards
    end
  end

  def down
    # F.21 (fizzy-i2m) re-adds FKs with the new varchar types after the
    # widening completes. Down here re-adds them with current (uuid) types.
    CARD_FK_TABLES.each do |table|
      next unless table_exists?(table)
      next if foreign_key_exists?(table, :cards)
      add_foreign_key table, :cards
    end
  end
end
