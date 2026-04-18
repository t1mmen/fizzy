require "test_helper"

class Cards::BoardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "update changes card board" do
    status = stub(success?: true, exitstatus: 0)

    card = nil
    Current.with(account: accounts("37s"), session: sessions(:kevin)) do
      card = boards(:writebook).cards.create!(id: "fizzy-move-001", title: "Beads mirror", creator: users(:kevin), status: :published)
    end
    new_board = boards(:private)
    actor = users(:kevin).identity.email_address
    old_label = card.board.membership_label
    new_label = new_board.membership_label

    seq = sequence("bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", actor, "--json", "show", card.id.to_s)
      .returns([JSON.dump([{ labels: [ old_label ] }]), "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", actor, "update", card.id.to_s, "--remove-label", old_label)
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", actor, "update", card.id.to_s, "--add-label", new_label)
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", actor, "update", card.id.to_s, "--status", "open")
      .returns(["", "", status]).in_sequence(seq)

    assert_not_equal new_board, card.board

    assert_changes -> { card.reload.board }, from: card.board, to: new_board do
      put card_board_path(card), params: { board_id: new_board.id }
    end

    assert_redirected_to card
  end

  test "update as JSON" do
    status = stub(success?: true, exitstatus: 0)

    card = nil
    Current.with(account: accounts("37s"), session: sessions(:kevin)) do
      card = boards(:writebook).cards.create!(id: "fizzy-move-002", title: "Beads mirror", creator: users(:kevin), status: :published)
    end
    new_board = boards(:private)
    actor = users(:kevin).identity.email_address
    old_label = card.board.membership_label
    new_label = new_board.membership_label

    seq = sequence("bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", actor, "--json", "show", card.id.to_s)
      .returns([JSON.dump([{ labels: [ old_label ] }]), "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", actor, "update", card.id.to_s, "--remove-label", old_label)
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", actor, "update", card.id.to_s, "--add-label", new_label)
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", actor, "update", card.id.to_s, "--status", "open")
      .returns(["", "", status]).in_sequence(seq)

    assert_not_equal new_board, card.board

    put card_board_path(card), params: { board_id: new_board.id }, as: :json

    assert_response :no_content
    assert_equal new_board, card.reload.board
  end
end
