require "test_helper"

class Cards::NotNowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "create" do
    card = cards(:logo)

    client = mock
    client.expects(:defer_issue).with(card.id)
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

      post card_not_now_path(card), as: :turbo_stream
      assert_card_container_rerendered(card)
  end

  test "create as JSON" do
    card = cards(:logo)

    client = mock
    client.expects(:defer_issue).with(card.id)
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)

    post card_not_now_path(card), as: :json

    assert_response :no_content
  end
end
