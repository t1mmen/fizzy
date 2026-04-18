require "test_helper"

class Cards::ClosuresControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "create" do
    card = cards(:logo)

    client = mock
    client.expects(:update_prior_status).with(card.id, card.beads_status.presence || "open")
    client.expects(:close_issue).with(card.id)
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    assert_changes -> { card.reload.closed? }, from: false, to: true do
      post card_closure_path(card), as: :turbo_stream
      assert_card_container_rerendered(card)
    end
  end

  test "destroy" do
    card = cards(:shipping)

    client = mock
    client.expects(:read_issue).with(card.id).returns({ "metadata" => { "fizzy" => { "prior_status" => "in_progress" } } })
    client.expects(:reopen_issue).with(card.id, restore_status: "in_progress")
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    assert_changes -> { card.reload.closed? }, from: true, to: false do
      delete card_closure_path(card), as: :turbo_stream
      assert_card_container_rerendered(card)
    end
  end

  test "create as JSON" do
    card = cards(:logo)

    assert_not card.closed?

    client = mock
    client.expects(:update_prior_status).with(card.id, card.beads_status.presence || "open")
    client.expects(:close_issue).with(card.id)
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    post card_closure_path(card), as: :json

    assert_response :no_content
    assert card.reload.closed?
  end

  test "destroy as JSON" do
    card = cards(:shipping)

    assert card.closed?

    client = mock
    client.expects(:read_issue).with(card.id).returns({ "metadata" => { "fizzy" => { "prior_status" => "in_progress" } } })
    client.expects(:reopen_issue).with(card.id, restore_status: "in_progress")
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    delete card_closure_path(card), as: :json

    assert_response :no_content
    assert_not card.reload.closed?
  end
end
