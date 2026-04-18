require "test_helper"

class Beads::Mirror::CommentMirrorTest < ActiveSupport::TestCase
  setup do
    @account = accounts("37s")
    @card = cards("logo")
    @user = users("jz")
    
    @beads_comment = {
      id: "comment-123",
      issue_id: @card.id,
      author: @user.identity.email_address,
      text: "Hello from Beads! @david",
      created_at: Time.current
    }
  end

  test "call creates a mirror comment row with mapped creator" do
    assert_difference "Comment.count", 1 do
      Beads::Mirror::CommentMirror.call(@beads_comment, account_id: @account.id)
    end

    comment = Comment.find("comment-123")
    assert_equal @user.id, comment.creator_id
    assert_equal @card.id, comment.card_id
  end

  test "call populates ActionText derived cache" do
    Beads::Mirror::CommentMirror.call(@beads_comment, account_id: @account.id)
    comment = Comment.find("comment-123")
    
    assert_match /<p>Hello from Beads! @david<\/p>/, comment.body.to_s
  end

  test "call explicitly syncs Search::Record" do
    assert_difference "Search::Record.where(searchable_type: 'Comment').count", 1 do
      Beads::Mirror::CommentMirror.call(@beads_comment, account_id: @account.id)
    end

    record = Search::Record.find_by(searchable_id: "comment-123", searchable_type: "Comment")
    assert_equal "Hello from Beads! @david", record.content
  end

  test "call derives a watch for the comment creator" do
    # Verify the check-and-create logic
    assert_difference "Watch.count", 1 do
      Beads::Mirror::CommentMirror.call(@beads_comment, account_id: @account.id)
    end

    assert @card.reload.watched_by?(@user)
  end

  test "call enqueues Mention::CreateJob" do
    assert_enqueued_with(job: Mention::CreateJob, args: ["comment-123", { creator_id: @user.id }]) do
      Beads::Mirror::CommentMirror.call(@beads_comment, account_id: @account.id)
    end
  end

  test "is idempotent on re-tick" do
    Beads::Mirror::CommentMirror.call(@beads_comment, account_id: @account.id)
    
    assert_no_difference "Comment.count" do
      assert_no_difference "ActionText::RichText.count" do
        assert_no_difference "Search::Record.where(searchable_type: 'Comment').count" do
          Beads::Mirror::CommentMirror.call(@beads_comment, account_id: @account.id)
        end
      end
    end
  end
end
