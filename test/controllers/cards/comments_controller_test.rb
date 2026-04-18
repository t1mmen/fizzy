require "test_helper"

class Cards::CommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @card = cards("logo")
    @comment = comments("logo_agreement_kevin")
    @kevin = users("kevin")
    sign_in_as @kevin
    
    @mock_client = mock("command_client")
    Fizzy::Beads::CommandClient.stubs(:current).returns(@mock_client)
  end

  test "create rewired to Beads" do
    @mock_client.expects(:add_comment).with(@card.id, "Agreed.").returns({
      "id" => "beads-comment-1",
      "issue_id" => @card.id,
      "author" => @kevin.identity.email_address,
      "text" => "Agreed.",
      "created_at" => Time.current.iso8601
    })

    assert_difference "Comment.count", 1 do
      post card_comments_path(@card), params: { comment: { body: "Agreed." } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "beads-comment-1", Comment.last.id
  end

  test "create on draft card is forbidden" do
    board = boards("writebook")
    draft_card = @card.account.cards.create!(
      title: "Draft Card", 
      status: :drafted, 
      creator: @kevin, 
      board: board,
      column: columns("writebook_triage")
    )
    
    # S2 F.4: Board membership is label-based.
    label = "#{Board::BOARD_LABEL_PREFIX}#{board.id}"
    tag = Tag.find_or_create_by!(account: @card.account, title: label)
    Tagging.create!(card: draft_card, tag: tag)

    assert_no_difference "Comment.count" do
      post card_comments_path(draft_card), params: { comment: { body: "This should be forbidden" } }, as: :json
    end

    assert_response :forbidden
  end

  test "edit is disabled" do
    get edit_card_comment_path(@card, @comment)
    assert_response :method_not_allowed
  end

  test "update is disabled" do
    put card_comment_path(@card, @comment), params: { comment: { body: "I've changed my mind" } }, as: :turbo_stream
    assert_response :method_not_allowed
  end

  test "destroy is disabled" do
    delete card_comment_path(@card, @comment), as: :turbo_stream
    assert_response :method_not_allowed
  end

  test "index as JSON still works (read-path)" do
    get card_comments_path(@card), as: :json
    assert_response :success
    assert_equal @card.comments.count, @response.parsed_body.count
  end

  test "show as JSON still works (read-path)" do
    get card_comment_path(@card, @comment), as: :json
    assert_response :success
    assert_equal @comment.id, @response.parsed_body["id"]
  end
end
