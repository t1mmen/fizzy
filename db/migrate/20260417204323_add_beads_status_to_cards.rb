class AddBeadsStatusToCards < ActiveRecord::Migration[8.0]
  def change
    add_column :cards, :beads_status, :string, limit: 32
    add_index :cards, :beads_status
  end
end
