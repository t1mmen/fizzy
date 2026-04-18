class AddBeadsStatusAndMatchLabelToColumns < ActiveRecord::Migration[8.0]
  # Per S2 §B.5: explicit projection-metadata columns so default + label-driven
  # custom columns can route Beads issues without abusing columns.name.
  #
  # beads_status: required for default columns (Todo/Doing/Blocked/Not now/Done)
  #   maps to Beads issues.status values (open/in_progress/blocked/deferred/closed).
  #   Nullable for now to allow safe backfill in I-S2 seeder (fizzy-eq4.2);
  #   downstream rewires (fizzy-eq4.5) tighten to NOT NULL after backfill.
  #
  # match_label: optional refinement for label-driven custom columns
  #   (e.g. "Doing — backend"). Card placed in first column whose
  #   beads_status matches AND (match_label nil OR card has that label).
  def change
    add_column :columns, :beads_status, :string, limit: 32
    add_column :columns, :match_label, :string
    add_index :columns, :beads_status
  end
end
