class AddBeadsMetadataToCards < ActiveRecord::Migration[8.0]
  # Per S10 §E.1 (decision locked in fizzy-e5m.1) + S9 §C.1.
  #
  # Mirror cache for Beads issues.metadata.fizzy.* JSON bucket. Populated by
  # the BeadsPoller's mirror_issue procedure on every tick (REPLACE semantics
  # — entire JSON object is overwritten, not deep-merged).
  #
  # Display/debug only. NOT used in indexed filter predicates (per S10 §A.2
  # invariant #2: filterable fields must be promoted to dedicated typed cols).
  def change
    add_column :cards, :beads_metadata, :json
  end
end
