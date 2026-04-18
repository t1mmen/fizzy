require "test_helper"

class Columns::Cards::Drops::StreamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "create" do
    card = cards(:text)

    assert_changes -> { card.reload.triaged? }, from: true, to: false do
      client = mock("beads_client")
      client.expects(:update_status).with(card.id, "open")
      Fizzy::Beads::CommandClient.stubs(:current).returns(client)

      post columns_card_drops_stream_path(card), as: :turbo_stream
      assert_response :success
    end
  end
end
