class WidenRemainingPolymorphicCardColumns < ActiveRecord::Migration[8.0]
  # Per S1 §F.14, §F.16, §F.19 — remaining polymorphic columns + search_records
  # FTS columns missed in the prior batch (20260417230000). Closes:
  #   fizzy-rpt  events.eventable_id (polymorphic)
  #   fizzy-hrf  reactions.reactable_id (polymorphic)
  #   fizzy-n9l  search_records card_id + searchable_id (16-shard MySQL prod;
  #              single search_records table in SQLite dev — same schema-shape
  #              widening either way)

  COLUMNS = [
    [ :events,          :eventable_id ],
    [ :reactions,       :reactable_id ],
    [ :search_records,  :card_id      ],
    [ :search_records,  :searchable_id ],
  ].freeze

  def up
    COLUMNS.each do |table, column|
      next unless table_exists?(table) && column_exists?(table, column)
      change_column table, column, :string, limit: 255, null: false
    end
  end

  def down
    COLUMNS.each do |table, column|
      next unless table_exists?(table) && column_exists?(table, column)
      change_column table, column, :uuid, null: false
    end
  end
end
