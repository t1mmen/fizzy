require "test_helper"

class Columns::Cards::Drops::NotNowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "create" do
    card = cards(:logo)

    client = mock
    client.expects(:defer_issue).with(card.id)
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

      post columns_card_drops_not_now_path(card), as: :turbo_stream
      assert_response :success
  end
end
