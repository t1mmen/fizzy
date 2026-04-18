require "application_system_test_case"

class BoardProjectionTest < ApplicationSystemTestCase
  test "board stream shows open cards by board membership label" do
    sign_in_as(users(:david))

    board = create_board_named("Projection board")
    open_card = create_mirrored_card_for(board, id: "fizzy-eq4-proj-open", title: "Board projection: open", beads_status: "open")

    visit board_url(board)

    within("#maybe") do
      assert_text open_card.title
    end
  end

  test "column pages project cards by beads_status (Doing/in_progress)" do
    sign_in_as(users(:david))

    board = create_board_named("Projection board (columns)")
    doing_column = board.columns.find_by!(beads_status: "in_progress")
    in_progress_card = create_mirrored_card_for(board, id: "fizzy-eq4-proj-doing", title: "Board projection: doing", beads_status: "in_progress")

    visit board_column_url(board, doing_column)

    assert_text in_progress_card.title
  end

  test "moving a Beads card between boards updates board membership and visibility" do
    sign_in_as(users(:david))

    from_board = create_board_named("Move-from board")
    to_board = create_board_named("Move-to board")

    card = create_mirrored_card_for(from_board, id: "fizzy-eq4-proj-move", title: "Board move (mirrored)", beads_status: "open")

    visit board_url(from_board)
    assert_text card.title

    visit edit_card_board_url(card)
    click_on to_board.name

    visit board_url(to_board)
    assert_text card.title

    visit board_url(from_board)
    assert_no_text card.title
  end

  test "boards without access are not listed for the user" do
    restricted_board = create_restricted_board_named("Restricted board (no kevin)")

    sign_in_as(users(:kevin))
    visit boards_url

    assert_no_text restricted_board.name
  end

  test "pinned overlay renders pinned cards on the current board" do
    sign_in_as(users(:kevin))

    card = cards(:layout)
    card.pin_by(users(:kevin))

    visit board_url(boards(:writebook))

    within("#pinned-overlay") do
      assert_text card.title
    end
  end

  private
    def create_board_named(name)
      creator = users(:david)
      Current.set(account: creator.account, user: creator, session: sessions(:david)) do
        Board.create!(name: name, creator: creator, account: creator.account, all_access: true)
      end
    end

    def create_restricted_board_named(name)
      creator = users(:david)
      Current.set(account: creator.account, user: creator, session: sessions(:david)) do
        Board.create!(name: name, creator: creator, account: creator.account, all_access: false)
      end
    end

    def create_mirrored_card_for(board, id:, title:, beads_status:)
      creator = users(:david)
      card = Current.set(account: creator.account, user: creator, session: sessions(:david)) do
        Card.create!(
          id: id,
          board: board,
          creator: creator,
          account: board.account,
          status: "published",
          beads_status: beads_status,
          title: title,
          last_active_at: Time.current
        )
      end

      tag = Tag.find_or_create_by!(account: board.account, title: board.membership_label)
      Tagging.find_or_create_by!(account: board.account, card: card, tag: tag)
      card
    end
end

