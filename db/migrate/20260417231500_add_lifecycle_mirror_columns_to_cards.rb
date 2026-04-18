class AddLifecycleMirrorColumnsToCards < ActiveRecord::Migration[8.0]
  # Per S4 §C.3 + bead fizzy-858.2:
  # Add lifecycle read columns to the MySQL/SQLite Card mirror so closure/defer
  # state can be read without touching Closure/NotNow tables.
  def change
    add_column :cards, :closed_at, :datetime
    add_column :cards, :defer_until, :datetime
    add_column :cards, :close_reason, :text

    add_index :cards, :closed_at
    add_index :cards, :defer_until
  end
end

