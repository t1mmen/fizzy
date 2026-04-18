class AddBeadsEventIdToEvents < ActiveRecord::Migration[8.0]
  # Per S8 §A.3 + §B.2: dedup key for poller-mirrored Events.
  #
  # Format (S8 §A.3):
  #   event:<beads_events.id>           — for Beads events rows
  #   event:<beads_events.id>:unassign  — reassignment value→value (S8 §A.4 v1.1)
  #   event:<beads_events.id>:assign    — paired with :unassign for reassignment
  #   comment:<beads_comments.id>       — for Beads comments rows
  #
  # Unique index allows nulls so Fizzy-originated Events (not yet poller-touched)
  # don't conflict. The poller uses Event.create! and catches RecordNotUnique
  # on this index as the success/dedup signal (S9 §B.1).
  def change
    add_column :events, :beads_event_id, :string
    add_index :events, :beads_event_id, unique: true
  end
end
