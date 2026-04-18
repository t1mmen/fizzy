require "test_helper"

class Cards::NotNowsControllerTest < ActionDispatch::IntegrationTest
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
      .with("bd", "--actor", "kevin@example.com", "defer", card.id.to_s)
      .returns(["", "", status]).in_sequence(seq)

      post card_not_now_path(card), as: :turbo_stream
      assert_card_container_rerendered(card)
  end

  test "create as JSON" do
    card = cards(:logo)

    status = stub(success?: true, exitstatus: 0)
    seq = sequence("bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "update", card.id.to_s, "--metadata", regexp_matches(/prior_status/))
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "defer", card.id.to_s)
      .returns(["", "", status]).in_sequence(seq)

    post card_not_now_path(card), as: :json

    assert_response :no_content
  end

  test "destroy" do
    card = cards(:logo)
    card.update_columns(defer_until: 1.day.from_now, updated_at: Time.current)

    status = stub(success?: true, exitstatus: 0)
    seq = sequence("bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "--json", "show", card.id.to_s)
      .returns([JSON.dump({ metadata: { fizzy: { prior_status: "in_progress" } } }), "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "undefer", card.id.to_s)
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "update", card.id.to_s, "--status", "in_progress")
      .returns(["", "", status]).in_sequence(seq)

    delete card_not_now_path(card), as: :turbo_stream
    assert_card_container_rerendered(card)

    assert_nil card.reload.defer_until
    assert_equal "in_progress", card.beads_status
  end

  test "destroy as JSON" do
    card = cards(:logo)
    card.update_columns(defer_until: 1.day.from_now, updated_at: Time.current)

    status = stub(success?: true, exitstatus: 0)
    seq = sequence("bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "--json", "show", card.id.to_s)
      .returns([JSON.dump({ metadata: { fizzy: { prior_status: "open" } } }), "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "undefer", card.id.to_s)
      .returns(["", "", status]).in_sequence(seq)
    Open3.expects(:capture3)
      .with("bd", "--actor", "kevin@example.com", "update", card.id.to_s, "--status", "open")
      .returns(["", "", status]).in_sequence(seq)

    delete card_not_now_path(card), as: :json

    assert_response :no_content
    assert_nil card.reload.defer_until
  end
end
