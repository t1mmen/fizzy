class RestoreCardGoldnesses < ActiveRecord::Migration[8.0]
  # Forward-restore: re-creates the card_goldnesses table dropped in
  # 20260417204500. The drop was premature — Card::Goldness model + Card::Golden
  # concern + multiple controllers/views still reference it. Cleanup tracked
  # under fizzy-7ka (reopened) which now requires code-side removal first.
  def up
    return if table_exists?(:card_goldnesses)
    create_table :card_goldnesses, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :card_id, null: false
      t.timestamps
      t.index :account_id
      t.index :card_id, unique: true
    end
  end

  def down
    drop_table :card_goldnesses if table_exists?(:card_goldnesses)
  end
end
