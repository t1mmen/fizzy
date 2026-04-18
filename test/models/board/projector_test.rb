require "test_helper"

# S2 F.6 (fizzy-eq4.6): Board::Projector provides MySQL-only query building
# blocks for Kanban + List board rendering (membership via labels, placement
# via cards.beads_status + columns.match_label, pinned overlay semantics).
class Board::ProjectorTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    Current.account = accounts("37s")
    Current.user = users(:david)

    Beads::CustomStatus.delete_all

    @board = Current.account.boards.create!(name: "Projected Board", creator: Current.user)
    @todo = @board.columns.find_by!(beads_status: "open")
    @done = @board.columns.find_by!(beads_status: "closed")

    @projector = Board::Projector.new(@board, user: Current.user)

    @open_card = create_board_card!(beads_status: "open", title: "Open")
    @unknown_status_card = create_board_card!(beads_status: "custom_wip", title: "Unknown status")
    @pinned_status_card = create_board_card!(beads_status: "pinned", title: "Pinned status")
  end

  test "pinned overlay includes beads_status='pinned' and excludes it from list_cards" do
    assert_includes @projector.pinned_overlay.pluck(:id), @pinned_status_card.id
    assert_not_includes @projector.list_cards.pluck(:id), @pinned_status_card.id
  end

  test "Todo/open column includes unknown/custom statuses (fallback visibility)" do
    ids = @projector.cards_for_column(@todo).pluck(:id)
    assert_includes ids, @open_card.id
    assert_includes ids, @unknown_status_card.id
  end

  test "Done column includes custom statuses categorized as done/frozen" do
    Beads::CustomStatus.create!(name: "released", category: Beads::CustomStatus::DONE)
    card = create_board_card!(beads_status: "released", title: "Released")

    assert_includes @projector.cards_for_column(@done).pluck(:id), card.id
    assert_not_includes @projector.cards_for_column(@todo).pluck(:id), card.id
  end

  test "label-driven custom columns take precedence over the catch-all column" do
    backend = @board.columns.create!(name: "Todo — backend", beads_status: "open", match_label: "backend")
    backend.update_column(:position, -1) # Column::Positioned before_create always appends; override for ordering test

    labeled_card = create_board_card!(beads_status: "open", title: "Backend task")
    labeled_card.toggle_tag_with("backend")

    columns = @board.columns.where(beads_status: "open").sorted.to_a
    first = columns.first
    last = columns.last

    assert_equal "backend", first.match_label
    assert_nil last.match_label, "expected the existing default Todo column to be the catch-all"

    assert_includes @projector.cards_for_column(first).pluck(:id), labeled_card.id
    assert_not_includes @projector.cards_for_column(last).pluck(:id), labeled_card.id
  end

  test "pinned overlay includes explicit user pins" do
    card = create_board_card!(beads_status: "open", title: "Pinned by user")
    card.pin_by(Current.user)

    assert_includes @projector.pinned_overlay.pluck(:id), card.id
  end

  private
    def create_board_card!(beads_status:, title:)
      card = Current.account.cards.create!(
        id: "eq4-6-#{SecureRandom.hex(6)}",
        title: title,
        status: "published",
        beads_status: beads_status,
        creator: Current.user,
        board: @board
      )
      card.toggle_tag_with(@board.membership_label)
      card
    end
end
