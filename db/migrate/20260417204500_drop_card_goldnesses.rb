class DropCardGoldnesses < ActiveRecord::Migration[8.0]
  def up
    drop_table :card_goldnesses
  end

  def down
    create_table :card_goldnesses, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :card_id, null: false
      t.timestamps
      t.index :account_id
      t.index :card_id, unique: true
    end
  end
end
