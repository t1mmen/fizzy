require "test_helper"

class ColumnTest < ActiveSupport::TestCase
  test "changing name/color does not touch cards (columns are projection rules)" do
    column = columns(:writebook_triage)
    card = column.board.cards.first

    assert_no_changes -> { card.reload.updated_at } do
      column.update!(name: "New Name")
    end

    assert_no_changes -> { card.reload.updated_at } do
      column.update!(color: "#FF0000")
    end

    assert_no_changes -> { card.reload.updated_at } do
      column.update!(updated_at: 1.hour.from_now)
    end
  end

  test "destroying a column does not touch board cards" do
    column = columns(:writebook_triage)
    card = column.board.cards.first

    assert_no_changes -> { card.reload.updated_at } do
      column.destroy
    end
  end
end
