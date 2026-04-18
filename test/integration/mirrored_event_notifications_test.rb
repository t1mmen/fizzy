require "test_helper"

class MirroredEventNotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @board = boards(:writebook)
    @card = cards(:logo)
    @david = users(:david)
    @kevin = users(:kevin)

    Notification.delete_all
    Notification::Bundle.delete_all

    # Fixtures default to bundle_email_frequency: never; enable bundling so we
    # can assert bundle-window behavior per S8 F.8.
    @kevin.settings.update!(bundle_email_frequency: :every_few_hours)
  end

  test "card_assigned event notifies the assignee (excluding creator) and creates a bundle window" do
    beads_event_id = "beads-event-assigned-001"
    beads_event = {
      id: beads_event_id,
      issue_id: @card.id,
      event_type: "updated",
      actor: @david.identity.email_address,
      created_at: Time.current,
      old_value: { "assignee" => nil }.to_json,
      new_value: { "assignee" => @kevin.identity.email_address }.to_json
    }

    assert_enqueued_with(job: NotifyRecipientsJob) do
      Beads::Mirror::EventMirror.call(beads_event, account: @board.account)
    end
    perform_enqueued_jobs(only: NotifyRecipientsJob)

    event = Event.find_by!(beads_event_id: "event:#{beads_event_id}")
    notification = Notification.find_by!(user: @kevin, card: @card)
    assert_equal event, notification.source
    assert_equal @david, notification.creator

    assert_nil Notification.find_by(user: @david, card: @card)

    bundle = @kevin.notification_bundles.pending.last
    assert_not_nil bundle
    assert_includes bundle.notifications, notification

    clear_enqueued_jobs
    assert_no_difference "Notification.count" do
      assert_no_enqueued_jobs(only: NotifyRecipientsJob) do
        Beads::Mirror::EventMirror.call(beads_event, account: @board.account)
      end
    end
  end

  test "comment_created event notifies watchers excluding author and creates a bundle window" do
    comment = Comment.create!(card: @card, creator: @david, body: "hello")

    assert_enqueued_with(job: NotifyRecipientsJob) do
      Beads::Mirror::CommentEvent.call(comment)
    end
    perform_enqueued_jobs(only: NotifyRecipientsJob)

    notification = Notification.find_by!(user: @kevin, card: @card)
    event = Event.find_by!(beads_event_id: "comment:#{comment.id}")
    assert_equal event, notification.source
    assert_equal @david, notification.creator

    assert_nil Notification.find_by(user: @david, card: @card)

    bundle = @kevin.notification_bundles.pending.last
    assert_not_nil bundle
    assert_includes bundle.notifications, notification

    clear_enqueued_jobs
    assert_no_difference "Notification.count" do
      assert_no_enqueued_jobs(only: NotifyRecipientsJob) do
        Beads::Mirror::CommentEvent.call(comment)
      end
    end
  end
end
