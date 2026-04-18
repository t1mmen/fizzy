require "test_helper"

class Cards::ClosuresControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "create" do
    card = cards(:logo)

    status = stub(success?: true, exitstatus: 0)
    seq = sequence("bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "update", card.id.to_s, "--metadata", regexp_matches(/prior_status/))
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "close", card.id.to_s)
      .returns(["", "", status]).in_sequence(seq)

    assert_changes -> { card.reload.closed? }, from: false, to: true do
      post card_closure_path(card), as: :turbo_stream
      assert_card_container_rerendered(card)
    end
  end

  test "destroy" do
    card = cards(:shipping)

    status = stub(success?: true, exitstatus: 0)
    seq = sequence("bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "--json", "show", card.id.to_s)
      .returns([JSON.dump({ metadata: { fizzy: { prior_status: "in_progress" } } }), "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "reopen", card.id.to_s)
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "update", card.id.to_s, "--status", "in_progress")
      .returns(["", "", status]).in_sequence(seq)

    assert_changes -> { card.reload.closed? }, from: true, to: false do
      delete card_closure_path(card), as: :turbo_stream
      assert_card_container_rerendered(card)
    end
  end

  test "create as JSON" do
    card = cards(:logo)

    assert_not card.closed?

    status = stub(success?: true, exitstatus: 0)
    seq = sequence("bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "update", card.id.to_s, "--metadata", regexp_matches(/prior_status/))
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "close", card.id.to_s)
      .returns(["", "", status]).in_sequence(seq)

    post card_closure_path(card), as: :json

    assert_response :no_content
    assert card.reload.closed?
  end

  test "destroy as JSON" do
    card = cards(:shipping)

    assert card.closed?

    status = stub(success?: true, exitstatus: 0)
    seq = sequence("bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "--json", "show", card.id.to_s)
      .returns([JSON.dump({ metadata: { fizzy: { prior_status: "in_progress" } } }), "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "reopen", card.id.to_s)
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "update", card.id.to_s, "--status", "in_progress")
      .returns(["", "", status]).in_sequence(seq)

    delete card_closure_path(card), as: :json

    assert_response :no_content
    assert_not card.reload.closed?
  end
end
