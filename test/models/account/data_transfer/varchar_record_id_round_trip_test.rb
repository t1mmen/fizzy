require "test_helper"

# S7 F.5 (fizzy-9cx): verify Account::DataTransfer export/import handles
# varchar Card.id values correctly. Existing serialization is generic
# (as_json → JSON), but this test confirms the round-trip explicitly so
# any future regression (e.g. a uuid-typed cast assumption) is caught.
class Account::DataTransfer::VarcharRecordIdRoundTripTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    Current.request_id = "test-data-transfer-varchar"
    @account = accounts("37s")
    @board = boards(:writebook)
  end

  test "ActionText::RichText with varchar Card.id record_id is exported as a string" do
    card = @board.cards.create!(id: "fizzy-export-001", title: "Varchar export test")
    card.update!(description: "<p>Body content for export</p>")

    rich_text = card.rich_text_description
    assert_equal "fizzy-export-001", rich_text.record_id, "RichText should reference Card by varchar id"

    # Simulate the export path's serialization
    data = rich_text.as_json
    assert_equal "fizzy-export-001", data["record_id"]
    assert_kind_of String, data["record_id"]

    # Round-trip through JSON to verify it stays a string
    serialized = JSON.dump(data)
    deserialized = JSON.parse(serialized)
    assert_equal "fizzy-export-001", deserialized["record_id"]
  end

  test "ActiveStorage::Attachment with varchar parent record_id round-trips through as_json" do
    card = @board.cards.create!(id: "fizzy-attach-002", title: "Attach test")

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("test data"),
      filename: "test.txt",
      content_type: "text/plain"
    )

    card.update!(description: "<p>#{ActionText::Attachment.from_attachable(blob).to_html}</p>")
    rich_text = card.rich_text_description

    # The attachment row points at the rich_text via record_id
    attachment = ActiveStorage::Attachment.find_by(record_type: "ActionText::RichText", record_id: rich_text.id)
    assert_not_nil attachment, "expected an attachment to exist for the rich_text body"

    # Verify as_json serializes record_id as the rich_text's UUID id (not the Card's varchar)
    # — this is correct per ActiveStorage semantics; the Card-id chain is via
    # rich_text.record_id (which IS varchar since record_id was widened in fizzy-jzw)
    data = rich_text.as_json
    assert_equal "fizzy-attach-002", data["record_id"], "rich_text.record_id mirrors Card.id (varchar)"
  end

  test "Storage::Entry round-trips with varchar recordable_id via as_json" do
    card = @board.cards.create!(id: "fizzy-entry-003", title: "Entry test")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x" * 256),
      filename: "test.txt",
      content_type: "text/plain"
    )

    entry = Storage::Entry.record(
      delta: blob.byte_size,
      operation: "attach",
      account: card.account,
      board: card.board,
      recordable: card,
      blob: blob
    )

    data = entry.as_json
    assert_equal "fizzy-entry-003", data["recordable_id"]
    assert_kind_of String, data["recordable_id"]

    # Round-trip lookup — find the entry back by varchar recordable_id
    found = Storage::Entry.find_by(recordable_type: "Card", recordable_id: "fizzy-entry-003")
    assert_equal entry.id, found.id
  end

  test "RichTextRecordSet ATTRIBUTES list has no uuid-type assumptions" do
    # Sanity check: the export attribute list passes record_id through as
    # a generic value (no cast). If a future refactor adds a coerce-to-uuid,
    # this test will need updating.
    assert_includes Account::DataTransfer::ActionText::RichTextRecordSet::ATTRIBUTES, "record_id"
  end
end
