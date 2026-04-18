class WidenCardIdColumnsToVarchar < ActiveRecord::Migration[8.0]
  # Per S1 §B.5–B.18b — combined widening of every column that references
  # cards.id (or any polymorphic recordable_id that may carry a Beads issue
  # id). Run AFTER fizzy-x2i drops the FK constraints; cards.id PK widen
  # (fizzy-05q) follows; fizzy-i2m re-adds FKs with new types.
  #
  # Closes 12 child beads of S1 (fizzy-669):
  #   fizzy-flu  closures.card_id
  #   fizzy-k48  taggings.card_id
  #   fizzy-0b8  comments.card_id
  #   fizzy-daf  steps.card_id
  #   fizzy-h6i  assignments.card_id
  #   fizzy-it5  watches.card_id
  #   fizzy-4wm  pins.card_id
  #   fizzy-2ae  notifications.card_id + notifications.source_id (polymorphic)
  #   fizzy-33r  mentions.source_id (polymorphic)
  #   fizzy-jzw  action_text_rich_texts.record_id (polymorphic)
  #   fizzy-cjs  active_storage_attachments.record_id (polymorphic)
  #   fizzy-0ic  storage_entries.recordable_id (polymorphic)
  #
  # Single migration to keep schema_sqlite.rb consistent and avoid 12
  # separate version bumps for what is essentially one logical change.

  CARD_ID_COLUMNS = [
    [ :closures,                    :card_id ],
    [ :taggings,                    :card_id ],
    [ :comments,                    :card_id ],
    [ :steps,                       :card_id ],
    [ :assignments,                 :card_id ],
    [ :watches,                     :card_id ],
    [ :pins,                        :card_id ],
    [ :notifications,               :card_id ],
  ].freeze

  POLYMORPHIC_COLUMNS = [
    [ :notifications,               :source_id     ],
    [ :mentions,                    :source_id     ],
    [ :action_text_rich_texts,      :record_id     ],
    [ :active_storage_attachments,  :record_id     ],
    [ :storage_entries,             :recordable_id ],
  ].freeze

  def up
    (CARD_ID_COLUMNS + POLYMORPHIC_COLUMNS).each do |table, column|
      next unless table_exists?(table) && column_exists?(table, column)
      change_column table, column, :string, limit: 255
    end
  end

  def down
    (CARD_ID_COLUMNS + POLYMORPHIC_COLUMNS).each do |table, column|
      next unless table_exists?(table) && column_exists?(table, column)
      change_column table, column, :uuid
    end
  end
end
