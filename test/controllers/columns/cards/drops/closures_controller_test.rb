require "test_helper"

class Columns::Cards::Drops::ClosuresControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "create" do
    card = cards(:logo)

    client = mock
    client.expects(:close_issue).with(card.id)
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    assert_changes -> { card.reload.closed? }, from: false, to: true do
      post columns_card_drops_closure_path(card), as: :turbo_stream
      assert_response :success
    end
  end
end
