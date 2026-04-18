require "test_helper"

class Fizzy::Beads::EventMapperTest < ActiveSupport::TestCase
  setup do
    @account = accounts("37s")
    @card = cards(:logo)
    @board = boards(:writebook)
    @private_board = boards(:private)
    @david = users(:david)
    @system = users(:system)
  end

  test "maps created -> card_published" do
    beads_event = {
      id: "beads-event-created-001",
      issue_id: @card.id,
      event_type: "created",
      actor: @david.identity.email_address,
      created_at: Time.current
    }

    payloads = Fizzy::Beads::EventMapper.call(beads_event, account: @account)
    assert_equal 1, payloads.size
    assert_equal "card_published", payloads.first[:action]
    assert_equal "event:beads-event-created-001", payloads.first[:beads_event_id]
    assert_equal @david, payloads.first[:creator]
    assert_equal @card.id, payloads.first[:eventable_id]
  end

  test "maps status open->closed -> card_closed" do
    beads_event = {
      id: "beads-event-closed-001",
      issue_id: @card.id,
      event_type: "updated",
      actor: @david.identity.email_address,
      old_value: { "status" => "open" }.to_json,
      new_value: { "status" => "closed" }.to_json,
      created_at: Time.current
    }

    payloads = Fizzy::Beads::EventMapper.call(beads_event, account: @account)
    assert_equal [ "card_closed" ], payloads.map { |p| p[:action] }
  end

  test "maps status closed->open -> card_reopened" do
    beads_event = {
      id: "beads-event-reopened-001",
      issue_id: @card.id,
      event_type: "updated",
      actor: @david.identity.email_address,
      old_value: { "status" => "closed" }.to_json,
      new_value: { "status" => "open" }.to_json,
      created_at: Time.current
    }

    payloads = Fizzy::Beads::EventMapper.call(beads_event, account: @account)
    assert_equal [ "card_reopened" ], payloads.map { |p| p[:action] }
  end

  test "maps title change -> card_title_changed with nested particulars" do
    beads_event = {
      id: "beads-event-title-001",
      issue_id: @card.id,
      event_type: "updated",
      actor: @david.identity.email_address,
      old_value: { "title" => "Old title" }.to_json,
      new_value: { "title" => "New title" }.to_json,
      created_at: Time.current
    }

    payload = Fizzy::Beads::EventMapper.call(beads_event, account: @account).first
    assert_equal "card_title_changed", payload[:action]
    assert_equal({ "particulars" => { "old_title" => "Old title", "new_title" => "New title" } }, payload[:particulars])
  end

  test "maps assignee nil->value -> card_assigned with assignee_ids" do
    beads_event = {
      id: "beads-event-assigned-001",
      issue_id: @card.id,
      event_type: "updated",
      actor: @david.identity.email_address,
      old_value: { "assignee" => nil }.to_json,
      new_value: { "assignee" => users(:kevin).identity.email_address }.to_json,
      created_at: Time.current
    }

    payload = Fizzy::Beads::EventMapper.call(beads_event, account: @account).first
    assert_equal "card_assigned", payload[:action]
    assert_equal({ "assignee_ids" => [ users(:kevin).id ] }, payload[:particulars])
  end

  test "maps assignee A->B as unassign+assign with suffix beads_event_id" do
    beads_event = {
      id: "beads-event-reassign-001",
      issue_id: @card.id,
      event_type: "updated",
      actor: @david.identity.email_address,
      old_value: { "assignee" => users(:kevin).identity.email_address }.to_json,
      new_value: { "assignee" => @david.identity.email_address }.to_json,
      created_at: Time.current
    }

    payloads = Fizzy::Beads::EventMapper.call(beads_event, account: @account)
    assert_equal [ "card_unassigned", "card_assigned" ], payloads.map { |p| p[:action] }
    assert_equal [ "event:beads-event-reassign-001:unassign", "event:beads-event-reassign-001:assign" ], payloads.map { |p| p[:beads_event_id] }
  end

  test "maps defer_until nil->timestamp to card_auto_postponed for system actor" do
    beads_event = {
      id: "beads-event-postpone-001",
      issue_id: @card.id,
      event_type: "updated",
      actor: "unknown actor",
      old_value: { "defer_until" => nil }.to_json,
      new_value: { "defer_until" => 1.day.from_now.iso8601 }.to_json,
      created_at: Time.current
    }

    payload = Fizzy::Beads::EventMapper.call(beads_event, account: @account).first
    assert_equal @system, payload[:creator]
    assert_equal "card_auto_postponed", payload[:action]
  end

  test "maps board label change to card_board_changed with board names in particulars" do
    old_label = "#{Board::BOARD_LABEL_PREFIX}#{@board.id}"
    new_label = "#{Board::BOARD_LABEL_PREFIX}#{@private_board.id}"

    beads_event = {
      id: "beads-event-board-001",
      issue_id: @card.id,
      event_type: "updated",
      actor: @david.identity.email_address,
      old_value: { "labels" => [ old_label ] }.to_json,
      new_value: { "labels" => [ new_label ] }.to_json,
      created_at: Time.current
    }

    payload = Fizzy::Beads::EventMapper.call(beads_event, account: @account).first
    assert_equal "card_board_changed", payload[:action]
    assert_equal @board.name, payload[:particulars].dig("particulars", "old_board")
    assert_equal @private_board.name, payload[:particulars].dig("particulars", "new_board")
  end

  test "maps open->in_progress as card_triaged with column label" do
    beads_event = {
      id: "beads-event-triage-001",
      issue_id: @card.id,
      event_type: "updated",
      actor: @david.identity.email_address,
      old_value: { "status" => "open" }.to_json,
      new_value: { "status" => "in_progress" }.to_json,
      created_at: Time.current
    }

    payload = Fizzy::Beads::EventMapper.call(beads_event, account: @account).first
    assert_equal "card_triaged", payload[:action]
    assert_equal "Doing", payload[:particulars].dig("particulars", "column")
  end

  test "maps in_progress->open as card_sent_back_to_triage" do
    beads_event = {
      id: "beads-event-triage-002",
      issue_id: @card.id,
      event_type: "updated",
      actor: @david.identity.email_address,
      old_value: { "status" => "in_progress" }.to_json,
      new_value: { "status" => "open" }.to_json,
      created_at: Time.current
    }

    payload = Fizzy::Beads::EventMapper.call(beads_event, account: @account).first
    assert_equal "card_sent_back_to_triage", payload[:action]
    assert_equal({}, payload[:particulars])
  end
end

