require "test_helper"

class BoardTest < ActiveSupport::TestCase
  test "membership_label returns the canonical fizzy/board/<id> string" do
    board = boards(:writebook)
    assert_equal "fizzy/board/#{board.id}", board.membership_label
  end

  test "membership_label is stable across renames (depends only on id)" do
    board = boards(:writebook)
    original_label = board.membership_label
    board.update!(name: "Renamed")
    assert_equal original_label, board.reload.membership_label
  end

  test "membership_label uses reserved BOARD_LABEL_PREFIX constant" do
    board = boards(:writebook)
    assert board.membership_label.start_with?(Board::BOARD_LABEL_PREFIX)
  end

  test ".board_label? returns true for any fizzy/board/* string" do
    assert Board.board_label?("fizzy/board/abc123")
    assert Board.board_label?("fizzy/board/")
    assert Board.board_label?("#{Board::BOARD_LABEL_PREFIX}xyz")
  end

  test ".board_label? returns false for unrelated labels" do
    assert_not Board.board_label?("backend")
    assert_not Board.board_label?("fizzy/system/foo")
    assert_not Board.board_label?("not-fizzy/board/x")
  end

  test ".board_label? handles nil safely" do
    assert_not Board.board_label?(nil)
  end
end
