class WidenRemainingCardIdJoinTablesToVarchar < ActiveRecord::Migration[8.0]
  # fizzy-858.11: after S1 widened cards.id to varchar(255), any remaining
  # UUID-typed (blob(16)) card_id join tables must be widened as well or
  # joins/scopes break under the sqlite uuid adapter (uuid => blob(16)).
  #
  # These tables are still exercised by legacy model code + tests
  # (Golden/Stallable/Postponable), even if later V2 work drops them.
  def change
    change_column :card_activity_spikes, :card_id, :string, limit: 255, null: false
    change_column :card_goldnesses, :card_id, :string, limit: 255, null: false
    change_column :card_not_nows, :card_id, :string, limit: 255, null: false
  end
end

