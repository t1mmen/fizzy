require "test_helper"

class Cards::NotNowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "create" do
    card = cards(:logo)

    client = mock
    client.expects(:update_prior_status).with(card.id, card.beads_status.presence || "open")
    client.expects(:defer_issue).with(card.id)
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

      post card_not_now_path(card), as: :turbo_stream
      assert_card_container_rerendered(card)
  end

  test "create as JSON" do
    card = cards(:logo)

    client = mock
    client.expects(:update_prior_status).with(card.id, card.beads_status.presence || "open")
    client.expects(:defer_issue).with(card.id)
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    post card_not_now_path(card), as: :json

    assert_response :no_content
  end

  test "destroy" do
    card = cards(:logo)
    card.update_columns(defer_until: 1.day.from_now, updated_at: Time.current)

    client = mock
    client.expects(:read_issue).with(card.id).returns({ "metadata" => { "fizzy" => { "prior_status" => "in_progress" } } })
    client.expects(:undefer_issue).with(card.id, restore_status: "in_progress")
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    delete card_not_now_path(card), as: :turbo_stream
    assert_card_container_rerendered(card)

    assert_nil card.reload.defer_until
    assert_equal "in_progress", card.beads_status
  end

  test "destroy as JSON" do
    card = cards(:logo)
    card.update_columns(defer_until: 1.day.from_now, updated_at: Time.current)

    client = mock
    client.expects(:read_issue).with(card.id).returns({ "metadata" => { "fizzy" => { "prior_status" => "open" } } })
    client.expects(:undefer_issue).with(card.id, restore_status: "open")
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    delete card_not_now_path(card), as: :json

    assert_response :no_content
    assert_nil card.reload.defer_until
  end
end
