class WidenCommentsIdToVarchar < ActiveRecord::Migration[8.2]
  # Per S6 §B.3: widen comments.id PK to varchar(255) to match Beads comment ids.
  # Also widen polymorphic reactable_id in reactions table to accommodate
  # string comment ids.

  def up
    # 1. Drop foreign keys pointing to comments.id if any remain
    # (S1 fizzy-x2i already dropped most; safety-check reactions)
    if foreign_key_exists?(:reactions, :comments)
      remove_foreign_key :reactions, :comments
    end

    # 2. Widen the primary key
    change_column :comments, :id, :string, limit: 255, null: false

    # 3. Widen columns referencing comments.id (polymorphic or direct)
    # Note: notifications.source_id, mentions.source_id, etc. were already
    # widened in 20260417230000_widen_card_id_columns_to_varchar.rb.
    # Missing: reactions.reactable_id.
    if table_exists?(:reactions) && column_exists?(:reactions, :reactable_id)
      change_column :reactions, :reactable_id, :string, limit: 255, null: false
    end
  end

  def down
    change_column :comments, :id, :uuid
    if table_exists?(:reactions) && column_exists?(:reactions, :reactable_id)
      change_column :reactions, :reactable_id, :uuid, null: false
    end
  end
end
