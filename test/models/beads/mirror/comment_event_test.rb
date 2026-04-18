require "test_helper"

# S8 F.4 (fizzy-n3l.4): mirroring a Beads comment creates exactly one
# comment_created Event row keyed by beads_event_id="comment:<id>", with
# Notifier fanout. Replays are idempotent.
class Beads::Mirror::CommentEventTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    Current.actor = "david@37signals.com"

    @account = accounts("37s")
    @board = boards(:writebook)
    @user = users(:david)
    @card = @board.cards.create!(
      id: "fizzy-n3l4-#{SecureRandom.hex(4)}",
      title: "Beads card",
      creator: @user,
      status: "published"
    )
    @comment = @card.comments.create!(creator: @user, body: "First mirrored comment")
  end

  teardown do
    Current.actor = nil
    Card.find_by(id: @card.id)&.destroy if @card
  end

  test "creates exactly one Event with action=comment_created keyed by beads_event_id=comment:<id>" do
    assert_difference "Event.count", 1 do
      Beads::Mirror::CommentEvent.call(@comment)
    end

    event = Event.find_by!(beads_event_id: "comment:#{@comment.id}")
    assert_equal "comment_created", event.action.to_s
    assert_equal @comment, event.eventable
    assert_equal @user, event.creator
    assert_equal @board, event.board
    assert_equal @account, event.account
  end

  test "is idempotent: replaying the same comment does not create a second Event" do
    Beads::Mirror::CommentEvent.call(@comment)

    assert_no_difference "Event.count" do
      Beads::Mirror::CommentEvent.call(@comment)
    end
  end

  test "uses comment.created_at as the Event created_at (preserving Beads chronology)" do
    @comment.update_column(:created_at, 3.days.ago)

    Beads::Mirror::CommentEvent.call(@comment)

    event = Event.find_by!(beads_event_id: "comment:#{@comment.id}")
    assert_in_delta @comment.created_at, event.created_at, 1.second
  end

  test "queues Notifier fanout (Notifiable after_create_commit fires NotifyRecipientsJob)" do
    assert_enqueued_with(job: NotifyRecipientsJob) do
      Beads::Mirror::CommentEvent.call(@comment)
    end
  end

  test "key_for returns the canonical dedup key" do
    assert_equal "comment:#{@comment.id}", Beads::Mirror::CommentEvent.key_for(@comment)
  end
end
