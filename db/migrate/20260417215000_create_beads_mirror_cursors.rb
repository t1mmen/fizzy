class CreateBeadsMirrorCursors < ActiveRecord::Migration[8.0]
  # Per S9 §A.2: per-source highwater cursor for the BeadsPoller engine.
  #
  # IMPORTANT — Beads UUID semantics: Beads `events.id` and `comments.id`
  # are MySQL `uuid()` (v1 timestamp-MAC, NOT UUIDv7), so they are NOT
  # monotonic across rows. Cursor MUST be timestamp-based, not id-based.
  #
  # Per-row meaning:
  #   source            — "events" | "comments" | "issues_snapshot"
  #   last_seen_at      — created_at of the highest-watermark Beads row
  #                       processed in the most recent successful tick.
  #   last_advanced_at  — wall-clock when the row was last advanced (used
  #                       by the periodic resync source = "issues_snapshot").
  #   processed_ids     — JSON array of Beads ids processed within the
  #                       overlap window `(last_seen_at - overlap, last_seen_at]`.
  #                       Replaced wholesale each tick (S9 §A.2 step 2 v1.1).
  def change
    create_table :beads_mirror_cursors, id: false do |t|
      t.string :source, null: false, primary_key: true
      t.datetime :last_seen_at, precision: 6
      t.datetime :last_advanced_at
      t.text :processed_ids
      t.timestamps
    end
  end
end
