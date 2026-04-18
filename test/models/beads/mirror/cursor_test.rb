require "test_helper"

class Beads::Mirror::CursorTest < ActiveSupport::TestCase
  test ".for finds or creates a cursor row per source" do
    cursor = Beads::Mirror::Cursor.for(Beads::Mirror::Cursor::EVENTS)
    assert_equal "events", cursor.source
    assert_equal cursor, Beads::Mirror::Cursor.for(Beads::Mirror::Cursor::EVENTS)
  end

  test "validates source is in known set" do
    cursor = Beads::Mirror::Cursor.new(source: "garbage")
    assert_not cursor.valid?
    assert_includes cursor.errors[:source], "is not included in the list"
  end

  test "processed_id_set returns [] when blank" do
    cursor = Beads::Mirror::Cursor.for(Beads::Mirror::Cursor::COMMENTS)
    assert_equal [], cursor.processed_id_set
  end

  test "processed_id_set parses JSON array of Beads ids" do
    cursor = Beads::Mirror::Cursor.for(Beads::Mirror::Cursor::COMMENTS)
    cursor.update!(processed_ids: '["abc", "def"]')
    assert_equal [ "abc", "def" ], cursor.processed_id_set
  end

  test "processed_id_set returns [] on malformed JSON" do
    cursor = Beads::Mirror::Cursor.for(Beads::Mirror::Cursor::COMMENTS)
    cursor.update_column(:processed_ids, "not-json")
    assert_equal [], cursor.processed_id_set
  end

  test "advance! sets last_seen_at + processed_ids + last_advanced_at" do
    cursor = Beads::Mirror::Cursor.for(Beads::Mirror::Cursor::EVENTS)
    ts = Time.current
    cursor.advance!(new_last_seen_at: ts, new_processed_ids: [ "id1", "id2" ])
    cursor.reload
    assert_in_delta ts.to_f, cursor.last_seen_at.to_f, 0.001
    assert_equal [ "id1", "id2" ], cursor.processed_id_set
    assert_not_nil cursor.last_advanced_at
  end

  test "OVERLAP_SECONDS = 2 (S9 §A.2 cursor semantics)" do
    assert_equal 2, Beads::Mirror::Cursor::OVERLAP_SECONDS
  end

  test "source constants match S9 spec" do
    assert_equal "events", Beads::Mirror::Cursor::EVENTS
    assert_equal "comments", Beads::Mirror::Cursor::COMMENTS
    assert_equal "issues_snapshot", Beads::Mirror::Cursor::ISSUES_SNAPSHOT
  end
end
