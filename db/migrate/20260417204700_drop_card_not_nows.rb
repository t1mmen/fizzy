class DropCardNotNows < ActiveRecord::Migration[8.0]
  def up
    drop_table :card_not_nows
  end

  def down
    create_table :card_not_nows, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :card_id, null: false
      t.uuid :user_id
      t.timestamps
      t.index :account_id
      t.index :card_id, unique: true
      t.index :user_id
    end
  end
end
