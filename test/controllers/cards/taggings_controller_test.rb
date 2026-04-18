require "test_helper"

class Cards::TaggingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "new" do
    get new_card_tagging_path(cards(:logo))
    assert_response :success
  end

  # ----- Legacy uuid-id Card path: direct AR mutation, no CommandClient -----

  test "toggle tag on (uuid card)" do
    Fizzy::Beads::CommandClient.any_instance.expects(:add_label).never
    assert_changes "cards(:logo).tagged_with?(tags(:mobile))", from: false, to: true do
      post card_taggings_path(cards(:logo)), params: { tag_title: tags(:mobile).title }, as: :turbo_stream
      assert_turbo_stream action: :replace, target: dom_id(cards(:logo), :tags)
    end
  end

  test "toggle tag off (uuid card)" do
    Fizzy::Beads::CommandClient.any_instance.expects(:add_label).never
    assert_changes "cards(:logo).tagged_with?(tags(:web))", from: true, to: false do
      post card_taggings_path(cards(:logo)), params: { tag_title: tags(:web).title }, as: :turbo_stream
      assert_turbo_stream action: :replace, target: dom_id(cards(:logo), :tags)
    end
  end

  test "toggle tag on as JSON (uuid card)" do
    card = cards(:logo)
    assert_not card.tagged_with?(tags(:mobile))
    post card_taggings_path(card), params: { tag_title: tags(:mobile).title }, as: :json
    assert_response :no_content
    assert card.reload.tagged_with?(tags(:mobile))
  end

  test "DELETE removes tag (uuid card)" do
    card = cards(:logo)
    assert card.tagged_with?(tags(:web))
    delete card_tagging_path(card, tags(:web).title), as: :turbo_stream
    assert_response :success
    assert_not card.reload.tagged_with?(tags(:web))
  end

  # ----- Beads-id Card path: delegate to CommandClient (poller mirrors back) -----

  test "POST on Beads-id card invokes CommandClient.add_label with normalized title" do
    card = beads_card!
    Fizzy::Beads::CommandClient.any_instance.expects(:add_label).with(card.id, "design").once
    post card_taggings_path(card), params: { tag_title: " Design " }, as: :turbo_stream
    assert_response :success
  end

  test "POST rejects leading-# title with 422 (LabelNormalizer policy)" do
    card = beads_card!
    Fizzy::Beads::CommandClient.any_instance.expects(:add_label).never
    post card_taggings_path(card), params: { tag_title: "#Design" }, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  test "DELETE on Beads-id card invokes CommandClient.remove_label with normalized title" do
    card = beads_card!
    Fizzy::Beads::CommandClient.any_instance.expects(:remove_label).with(card.id, "mobile").once
    delete card_tagging_path(card, "Mobile"), as: :turbo_stream
    assert_response :success
  end

  test "POST rejects fizzy/ reserved namespace with 422" do
    card = beads_card!
    Fizzy::Beads::CommandClient.any_instance.expects(:add_label).never
    post card_taggings_path(card), params: { tag_title: "fizzy/board/abc" }, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  test "POST rejects blank title (after normalization) with 422" do
    card = beads_card!
    Fizzy::Beads::CommandClient.any_instance.expects(:add_label).never
    post card_taggings_path(card), params: { tag_title: "###" }, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  private
    def beads_card!
      @beads_card ||= boards(:writebook).cards.create!(
        id: "fizzy-tag-#{SecureRandom.hex(4)}",
        title: "Beads card for tagging",
        creator: users(:kevin)
      )
    end
end
