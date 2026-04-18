class CreateBeadsCustomStatuses < ActiveRecord::Migration[8.0]
  # Per S9 §C.2 (fizzy-pmi.4): mirror Beads custom_statuses(name, category)
  # into MySQL so the S2 board projector can route custom statuses without
  # a per-tick Beads SQL query (cf. S10 §A.2 invariant — filterable fields
  # MUST be sidecar-indexable).
  #
  # Refreshed wholesale by BeadsResync (fizzy-pmi.8) on the periodic
  # full-sweep cadence (low frequency — custom statuses change rarely).
  def change
    create_table :beads_custom_statuses, id: false do |t|
      t.string :name,     null: false, primary_key: true, limit: 64
      t.string :category, null: false, limit: 32
      t.datetime :updated_at, null: false
    end
    add_index :beads_custom_statuses, :category
  end
end
