require "test_helper"

# S2 F.2: every newly-created Board gets the 5 default columns seeded with
# the canonical beads_status mapping (Todo/Doing/Blocked/Not now/Done).
# Idempotent: re-running on a partially-seeded board adds only missing rows.
class Board::DefaultColumnsTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    @account = accounts("37s")
  end

  test "creating a Board seeds 5 default columns with canonical beads_status mapping" do
    board = nil
    assert_difference "Column.count", 5 do
      board = @account.boards.create!(name: "New Board", creator: Current.user)
    end

    statuses = board.columns.order(:position).pluck(:beads_status)
    assert_equal [ "open", "in_progress", "blocked", "deferred", "closed" ], statuses

    names = board.columns.order(:position).pluck(:name)
    assert_equal [ "Todo", "Doing", "Blocked", "Not now", "Done" ], names
  end

  test "default columns get sequential positions starting from 0" do
    board = @account.boards.create!(name: "Positions Test", creator: Current.user)
    positions = board.columns.order(:position).pluck(:position)
    assert_equal positions, positions.sort
    assert_equal 5, positions.uniq.size, "all positions should be unique"
  end

  test "seed_default_columns is idempotent — second call adds no duplicates" do
    board = @account.boards.create!(name: "Idempotent Test", creator: Current.user)
    initial_count = board.columns.count

    assert_no_difference "Column.count" do
      board.seed_default_columns
    end

    assert_equal initial_count, board.reload.columns.count
  end

  test "seed_default_columns fills in missing statuses but preserves existing" do
    board = @account.boards.create!(name: "Partial Test", creator: Current.user)
    # Delete some columns to simulate a partially-seeded board
    board.columns.where(beads_status: [ "blocked", "deferred" ]).destroy_all

    assert_difference "Column.count", 2 do
      board.seed_default_columns
    end

    statuses = board.columns.order(:position).pluck(:beads_status).sort
    assert_equal [ "blocked", "closed", "deferred", "in_progress", "open" ], statuses
  end

  test "DEFAULT_COLUMNS is frozen and matches S2 §B.2 spec" do
    assert Board::DefaultColumns::DEFAULT_COLUMNS.frozen?
    expected = [ "open", "in_progress", "blocked", "deferred", "closed" ]
    actual = Board::DefaultColumns::DEFAULT_COLUMNS.map { |c| c[:beads_status] }
    assert_equal expected, actual
  end
end
