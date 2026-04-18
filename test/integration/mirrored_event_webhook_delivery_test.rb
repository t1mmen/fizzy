require "test_helper"

class MirroredEventWebhookDeliveryTest < ActionDispatch::IntegrationTest
  setup do
    @board = boards(:writebook)
    @card = cards(:logo)
    @creator = users(:kevin)
    @webhook = Webhook.create!(
      board: @board,
      name: "Mirrored webhook",
      url: "https://example.com/webhook",
      subscribed_actions: [ "card_closed" ],
      active: true
    )
  end

  test "mirroring the same beads_event_id only triggers one webhook delivery" do
    beads_event_id = "beads-event-001"

    assert_equal 0, @webhook.deliveries.count

    assert_enqueued_with(job: Event::WebhookDispatchJob) do
      mirror_event!(beads_event_id:)
    end
    perform_enqueued_jobs(only: Event::WebhookDispatchJob)
    assert_equal 1, @webhook.deliveries.count

    # Re-mirroring should no-op due to the unique index on events.beads_event_id.
    clear_enqueued_jobs
    assert_no_changes -> { @webhook.deliveries.count } do
      assert_no_enqueued_jobs(only: Event::WebhookDispatchJob) do
        mirror_event!(beads_event_id:)
      end
    end
  end

  private
    def mirror_event!(beads_event_id:)
      beads_event = {
        id: beads_event_id,
        issue_id: @card.id,
        event_type: "closed",
        actor: @creator.identity.email_address,
        created_at: Time.current
      }

      Beads::Mirror::EventMirror.call(beads_event, account: @board.account)
    end
end
