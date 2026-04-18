class WidenCardsIdPkToVarchar < ActiveRecord::Migration[8.0]
  # KEYSTONE migration — per S1 §F.20 (fizzy-05q). Changes cards.id PK from
  # uuid (binary 16 in MySQL, BLOB(16) in SQLite via UuidPrimaryKeyDefault)
  # to varchar(255) so cards.id can carry Beads issue id strings (e.g.
  # "fizzy-669"). All child FK columns must already be widened (12 columns
  # closed in batch migration 20260417230000_widen_card_id_columns_to_varchar
  # via fizzy-flu/k48/0b8/daf/h6i/it5/4wm/2ae/33r/jzw/cjs/0ic) and FK
  # constraints must already be dropped (fizzy-x2i).
  #
  # Re-add of FK constraints with new varchar types is fizzy-i2m (F.21).
  # Schema verification + rollback test is fizzy-iwk (F.22).
  def up
    change_column :cards, :id, :string, limit: 255, null: false
  end

  def down
    change_column :cards, :id, :uuid, null: false
  end
end
