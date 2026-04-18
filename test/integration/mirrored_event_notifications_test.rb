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
    event = nil

    assert_enqueued_with(job: NotifyRecipientsJob) do
      event = mirror_card_assigned_event!(assignee: @kevin, creator: @david, beads_event_id: "beads-event-assigned-001")
    end
    perform_enqueued_jobs(only: NotifyRecipientsJob)

    notification = Notification.find_by!(user: @kevin, card: @card)
    assert_equal event, notification.source
    assert_equal @david, notification.creator

    assert_nil Notification.find_by(user: @david, card: @card)

    bundle = @kevin.notification_bundles.pending.last
    assert_not_nil bundle
    assert_includes bundle.notifications, notification
  end

  test "comment_created event notifies watchers excluding author and creates a bundle window" do
    comment = Comment.create!(card: @card, creator: @david, body: "hello")
    event = nil

    assert_enqueued_with(job: NotifyRecipientsJob) do
      event = mirror_comment_created_event!(comment:, creator: @david, beads_event_id: "beads-event-comment-001")
    end
    perform_enqueued_jobs(only: NotifyRecipientsJob)

    notification = Notification.find_by!(user: @kevin, card: @card)
    assert_equal event, notification.source
    assert_equal @david, notification.creator

    assert_nil Notification.find_by(user: @david, card: @card)

    bundle = @kevin.notification_bundles.pending.last
    assert_not_nil bundle
    assert_includes bundle.notifications, notification
  end

  private
    def mirror_card_assigned_event!(assignee:, creator:, beads_event_id:)
      Event.create!(
        board: @board,
        creator: creator,
        eventable: @card,
        action: "card_assigned",
        beads_event_id: beads_event_id,
        particulars: { assignee_ids: [ assignee.id ] }
      )
    rescue ActiveRecord::RecordNotUnique
      Event.find_by!(beads_event_id: beads_event_id)
    end

    def mirror_comment_created_event!(comment:, creator:, beads_event_id:)
      Event.create!(
        board: @board,
        creator: creator,
        eventable: comment,
        action: "comment_created",
        beads_event_id: beads_event_id,
        particulars: {}
      )
    rescue ActiveRecord::RecordNotUnique
      Event.find_by!(beads_event_id: beads_event_id)
    end
end
