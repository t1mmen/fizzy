require "test_helper"

class Cards::TriagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "create" do
    card = cards(:buy_domain)
    column = columns(:writebook_in_progress)

    client = mock("beads_client")
    client.expects(:update_status).with(card.id, "in_progress")
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    assert_changes -> { card.reload.beads_status }, from: "open", to: "in_progress" do
      post card_triage_path(card, column_id: column.id)
      assert_redirected_to card
    end
  end

  test "destroy" do
    card = cards(:text)

    client = mock("beads_client")
    client.expects(:update_status).with(card.id, "open")
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    assert_changes -> { card.reload.beads_status }, from: "in_progress", to: "open" do
      delete card_triage_path(card), as: :turbo_stream
      assert_redirected_to card
    end
  end

  test "create as JSON" do
    card = cards(:buy_domain)
    column = columns(:writebook_in_progress)

    client = mock("beads_client")
    client.expects(:update_status).with(card.id, "in_progress")
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    post card_triage_path(card, column_id: column.id), as: :json

    assert_response :no_content
    assert_equal "in_progress", card.reload.beads_status
  end

  test "destroy as JSON" do
    card = cards(:text)

    client = mock("beads_client")
    client.expects(:update_status).with(card.id, "open")
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    delete card_triage_path(card), as: :json

    assert_response :no_content
    assert_equal "open", card.reload.beads_status
  end
end
