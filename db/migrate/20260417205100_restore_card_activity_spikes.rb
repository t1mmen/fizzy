class RestoreCardActivitySpikes < ActiveRecord::Migration[8.0]
  # Forward-restore: re-creates the card_activity_spikes table dropped in
  # 20260417204600. The drop was premature — Card::ActivitySpike model +
  # Card::Stallable concern + Detector + DetectionJob + bubble_controller.js
  # still reference it. Cleanup tracked under fizzy-ml5 (reopened) which now
  # requires code-side removal first.
  def up
    return if table_exists?(:card_activity_spikes)
    create_table :card_activity_spikes, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :card_id, null: false
      t.timestamps
      t.index :account_id
      t.index :card_id, unique: true
    end
  end

  def down
    drop_table :card_activity_spikes if table_exists?(:card_activity_spikes)
  end
end
