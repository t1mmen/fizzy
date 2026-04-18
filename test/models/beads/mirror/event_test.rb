require "test_helper"

# S9 F.7 (fizzy-pmi.7): event mirror procedure. Translates a Beads events
# row through Fizzy::Beads::EventMapper and Event.create!s the resulting
# payloads with idempotent dedup via events.beads_event_id.
class Beads::Mirror::EventTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    Current.actor = "david@37signals.com"
    Current.account = accounts("37s")

    @account = Current.account
    @board = boards(:writebook)
    @user = users(:david)
    @card = @board.cards.create!(
      id: "fizzy-pmi7-#{SecureRandom.hex(4)}",
      title: "Card under mirror",
      creator: @user,
      status: "published"
    )
  end

  teardown do
    Current.actor = nil
    Current.account = nil
    Card.find_by(id: @card.id)&.destroy if @card
  end

  test "mapped event creates an Event keyed by beads_event_id" do
    beads_event_id = SecureRandom.uuid
    beads_event = {
      id: beads_event_id,
      issue_id: @card.id,
      event_type: "created",
      actor: @user.identity.email_address,
      created_at: Time.current
    }

    assert_difference "Event.count", 1 do
      Beads::Mirror::Event.call(beads_event)
    end

    event = Event.find_by!(beads_event_id: "event:#{beads_event_id}")
    assert_equal "card_published", event.action.to_s
    assert_equal @card, event.eventable
    assert_equal @board, event.board
    assert_equal @account, event.account
    assert_equal @user, event.creator
  end

  test "duplicate beads_event_id is silently swallowed (idempotent replay)" do
    beads_event_id = SecureRandom.uuid
    beads_event = {
      id: beads_event_id,
      issue_id: @card.id,
      event_type: "closed",
      actor: @user.identity.email_address,
      created_at: Time.current
    }

    Beads::Mirror::Event.call(beads_event)

    assert_no_difference "Event.count" do
      assert_nothing_raised { Beads::Mirror::Event.call(beads_event) }
    end
  end

  test "unmapped event types produce no Event row" do
    beads_event = {
      id: SecureRandom.uuid,
      issue_id: @card.id,
      event_type: "labels_added",  # not in EventMapper's case list
      actor: @user.identity.email_address,
      created_at: Time.current
    }

    assert_no_difference "Event.count" do
      result = Beads::Mirror::Event.call(beads_event)
      assert_empty result
    end
  end

  test "Notifiable fires NotifyRecipientsJob via Event after_create_commit" do
    beads_event = {
      id: SecureRandom.uuid,
      issue_id: @card.id,
      event_type: "created",
      actor: @user.identity.email_address,
      created_at: Time.current
    }

    assert_enqueued_with(job: NotifyRecipientsJob) do
      Beads::Mirror::Event.call(beads_event)
    end
  end

  test "WebhookDispatchJob is enqueued via Event after_create_commit" do
    beads_event = {
      id: SecureRandom.uuid,
      issue_id: @card.id,
      event_type: "created",
      actor: @user.identity.email_address,
      created_at: Time.current
    }

    assert_enqueued_with(job: Event::WebhookDispatchJob) do
      Beads::Mirror::Event.call(beads_event)
    end
  end

  test "skips silently when issue_id resolves to no Card (orphan event)" do
    beads_event = {
      id: SecureRandom.uuid,
      issue_id: "fizzy-orphaned-no-card",
      event_type: "created",
      actor: @user.identity.email_address,
      created_at: Time.current
    }

    assert_no_difference "Event.count" do
      result = Beads::Mirror::Event.call(beads_event)
      assert_empty result.compact
    end
  end
end
