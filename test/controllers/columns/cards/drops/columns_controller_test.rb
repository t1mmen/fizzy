require "test_helper"

class Columns::Cards::Drops::ColumnsControllerTest < ActionDispatch::IntegrationTest
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
      post columns_card_drops_column_path(card, column_id: column.id), as: :turbo_stream
      assert_response :success
    end
  end
end
