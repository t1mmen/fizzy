require "test_helper"

class Cards::CommentMentionsIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @card = cards("logo")
    @david = users("david")
    @jz = users("jz")
  end

  test "mentions are derived from plaintext in beads-backed comments" do
    # Simulate a mirrored comment with plaintext mention
    # Fixture identities use @37signals.com
    beads_comment = {
      id: "beads-comment-999",
      issue_id: @card.id,
      author: @david.identity.email_address,
      text: "Hey @jz@37signals.com, look at this!",
      created_at: Time.current
    }

    assert_difference "Mention.count", 1 do
      # Mentions are derived during mirror procedure (S6 F.8)
      Beads::Mirror::CommentMirror.call(beads_comment, account_id: @card.account_id)
      
      # Mention::CreateJob is enqueued by CommentMirror
      perform_enqueued_jobs
    end

    mention = Mention.find_by(mentionee: @jz, source_type: "Comment", source_id: "beads-comment-999")
    assert_not_nil mention
    assert_equal @david, mention.mentioner
  end

  test "mentions are derived from handles in beads-backed comments" do
    beads_comment = {
      id: "beads-comment-888",
      issue_id: @card.id,
      author: @david.identity.email_address,
      text: "Hey @jz!",
      created_at: Time.current
    }

    assert_difference "Mention.count", 1 do
      Beads::Mirror::CommentMirror.call(beads_comment, account_id: @card.account_id)
      perform_enqueued_jobs
    end

    assert Mention.exists?(mentionee: @jz, source_id: "beads-comment-888")
  end
end
