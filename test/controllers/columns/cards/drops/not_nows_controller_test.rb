require "test_helper"

class Columns::Cards::Drops::NotNowsControllerTest < ActionDispatch::IntegrationTest
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

      post columns_card_drops_not_now_path(card), as: :turbo_stream
      assert_response :success
  end
end
