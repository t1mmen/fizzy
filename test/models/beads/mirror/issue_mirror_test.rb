require "test_helper"

# S9 F.3 (fizzy-pmi.3): per-issue mirror procedure. Takes a Beads-issue-
# shaped object, upserts Card mirror row, syncs Search::Record.
class Beads::Mirror::IssueMirrorTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    @account = accounts("37s")
    @board = boards(:writebook)
  end

  test "call with Hash beads_issue creates a Card mirror row" do
    beads = {
      id: "fizzy-test-001",
      status: "open",
      title: "Test issue",
      closed_at: nil,
      defer_until: nil
    }

    card = Beads::Mirror::IssueMirror.call(beads, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)

    assert_not_nil card
    assert_equal "fizzy-test-001", card.id
    assert_equal "open", card.beads_status
    assert_equal "Test issue", card.title
  end

  test "call is idempotent — re-running with same beads_issue does not create duplicate" do
    beads = { id: "fizzy-test-002", status: "in_progress", title: "Idempotent" }

    Beads::Mirror::IssueMirror.call(beads, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
    assert_no_difference "Card.count" do
      Beads::Mirror::IssueMirror.call(beads, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
    end
  end

  test "call updates existing Card mirror row when beads_issue changes" do
    beads = { id: "fizzy-test-003", status: "open", title: "Original" }
    Beads::Mirror::IssueMirror.call(beads, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)

    beads_updated = beads.merge(status: "closed", closed_at: Time.current, title: "Updated")
    card = Beads::Mirror::IssueMirror.call(beads_updated, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)

    assert_equal "closed", card.beads_status
    assert_equal "Updated", card.title
    assert_not_nil card.closed_at
  end

  test "call with string keys (JSON-style Hash) reads correctly" do
    beads = {
      "id" => "fizzy-test-004",
      "status" => "blocked",
      "title" => "String keys"
    }

    card = Beads::Mirror::IssueMirror.call(beads, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
    assert_equal "blocked", card.beads_status
  end

  test "call extracts metadata.fizzy bucket into cards.beads_metadata" do
    beads = {
      id: "fizzy-test-005",
      status: "open",
      title: "With metadata",
      metadata: { "fizzy" => { "prior_status" => "in_progress" } }
    }

    card = Beads::Mirror::IssueMirror.call(beads, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
    assert_equal({ "prior_status" => "in_progress" }, card.beads_metadata)
  end

  test "call ignores metadata if no fizzy bucket present" do
    beads = {
      id: "fizzy-test-006",
      status: "open",
      title: "No fizzy bucket",
      metadata: { "other" => { "key" => "value" } }
    }

    card = Beads::Mirror::IssueMirror.call(beads, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
    assert_nil card.beads_metadata
  end

  test "call returns nil and skips when beads_issue.id is blank" do
    assert_nothing_raised do
      result = Beads::Mirror::IssueMirror.call({ id: nil, status: "open" }, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
      assert_nil result
    end
  end

  test "call works with AR-like object (responds to .id / .status / .title)" do
    beads_struct = Struct.new(:id, :status, :title, :closed_at, :defer_until, :close_reason, :metadata, keyword_init: true)
    beads = beads_struct.new(id: "fizzy-test-007", status: "deferred", title: "Struct input", closed_at: nil, defer_until: 1.day.from_now, close_reason: nil, metadata: nil)

    card = Beads::Mirror::IssueMirror.call(beads, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
    assert_equal "deferred", card.beads_status
    assert_not_nil card.defer_until
  end

  test "call creates a Search::Record for the mirrored Card" do
    beads = { id: "fizzy-test-008", status: "open", title: "Searchable" }

    Beads::Mirror::IssueMirror.call(beads, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)

    record = Search::Record.find_by(searchable_type: "Card", searchable_id: "fizzy-test-008")
    assert_not_nil record
    assert_equal "Searchable", record.title
    assert_includes record.content, "Searchable"
    assert_includes record.content, "open"
  end
end
