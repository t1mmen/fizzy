require "test_helper"

# S5 F.9 (fizzy-4az): integration test for TaggingsController + CommandClient
# rewire. Verifies the full URL → controller → CommandClient.add_label /
# .remove_label path, plus the LabelNormalizer + ReservedNamespace 422 gates.
class Cards::TaggingsFlowTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    sign_in_as :david
    Rails.application.config.x.fizzy.install_hostname = "test.fizzy.localhost"

    @account = accounts("37s")
    @board = boards(:writebook)
    @card_id = "fizzy-4az-#{SecureRandom.hex(4)}"
    @beads_card = @board.cards.create!(id: @card_id, title: "Beads card", creator: users(:david))
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = nil
    Card.find_by(id: @card_id)&.destroy if @card_id
  end

  test "POST with valid title invokes CommandClient.add_label with normalized argv" do
    Fizzy::Beads::CommandClient.any_instance.expects(:add_label).with(@beads_card.id, "backend").once

    post(
      "/#{@account.external_account_id}/cards/#{@beads_card.number}/taggings",
      params: { tag_title: " Backend " },
      as: :turbo_stream
    )
    assert_response :success
  end

  test "DELETE invokes CommandClient.remove_label with normalized argv" do
    Fizzy::Beads::CommandClient.any_instance.expects(:remove_label).with(@beads_card.id, "frontend").once

    delete(
      "/#{@account.external_account_id}/cards/#{@beads_card.number}/taggings/Frontend",
      as: :turbo_stream
    )
    assert_response :success
  end

  test "POST with leading-# title returns 422 (LabelNormalizer rejection)" do
    Fizzy::Beads::CommandClient.any_instance.expects(:add_label).never

    post(
      "/#{@account.external_account_id}/cards/#{@beads_card.number}/taggings",
      params: { tag_title: "#Backend" },
      as: :turbo_stream
    )
    assert_response :unprocessable_entity
  end

  test "POST with reserved fizzy/ namespace returns 422" do
    Fizzy::Beads::CommandClient.any_instance.expects(:add_label).never

    post(
      "/#{@account.external_account_id}/cards/#{@beads_card.number}/taggings",
      params: { tag_title: "fizzy/board/abc" },
      as: :turbo_stream
    )
    assert_response :unprocessable_entity
  end

  test "DELETE with reserved fizzy/ namespace returns 422" do
    Fizzy::Beads::CommandClient.any_instance.expects(:remove_label).never

    delete(
      "/#{@account.external_account_id}/cards/#{@beads_card.number}/taggings/fizzy%2Fboard%2Fabc",
      as: :turbo_stream
    )
    assert_response :unprocessable_entity
  end
end
