require "test_helper"

# S7 F.1: verify post-S1 widening that ActiveStorage attachments,
# ActionText rich text, and Storage::Entry rows all round-trip cleanly
# with a varchar(255) Card.id (Beads issue id format like "fizzy-abc").
class Storage::VarcharRecordIdRoundTripTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    Current.request_id = "test-varchar-round-trip"
    @account = accounts("37s")
    @board = boards(:writebook)
  end

  test "Card with Beads-style varchar id can be created" do
    card = nil
    assert_nothing_raised do
      card = @board.cards.create!(
        id: "fizzy-test-abc-123",
        title: "Varchar id card"
      )
    end
    assert_equal "fizzy-test-abc-123", card.id
    assert_equal "fizzy-test-abc-123", Card.find("fizzy-test-abc-123").id
  end

  test "Card with varchar id can attach ActionText description with inline blob" do
    card = @board.cards.create!(id: "fizzy-test-rt-456", title: "RT card")

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("test content"),
      filename: "test.txt",
      content_type: "text/plain"
    )

    attachment_html = ActionText::Attachment.from_attachable(blob).to_html
    card.update!(description: "<p>Inline: #{attachment_html}</p>")

    rich_text = card.rich_text_description
    assert_not_nil rich_text
    assert_equal card.id, rich_text.record_id
    assert_equal "Card", rich_text.record_type
    assert rich_text.embeds.any?, "expected rich text to have at least one embedded blob"
  end

  test "Storage::Tracked#storage_attachments_for_records resolves RichText parents for varchar Card ids" do
    card = @board.cards.create!(id: "fizzy-test-storage-789", title: "Storage card")

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x" * 1024),
      filename: "embed.txt",
      content_type: "text/plain"
    )

    attachment_html = ActionText::Attachment.from_attachable(blob).to_html
    card.update!(description: "<p>#{attachment_html}</p>")

    grouped = card.send(:storage_attachments_for_records, [ card ])
    assert_includes grouped.keys, card
    assert_equal 1, grouped[card].size
    assert_equal blob.id, grouped[card].first.blob_id
  end

  test "Storage::Entry.record writes ledger row keyed by varchar recordable_id" do
    card = @board.cards.create!(id: "fizzy-test-ledger-xyz", title: "Ledger card")

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("y" * 512),
      filename: "ledger.txt",
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

    assert_not_nil entry
    assert_equal "fizzy-test-ledger-xyz", entry.recordable_id
    assert Storage::Entry.where(recordable_id: "fizzy-test-ledger-xyz").exists?
  end

  test "fixture-based Card (UUID id) and Beads-style Card (varchar id) coexist" do
    legacy_card = cards(:logo)  # UUID-style id from fixtures
    beads_card = @board.cards.create!(id: "fizzy-coexist-001", title: "New world")

    # Both queryable via the same Card.find interface
    assert_equal legacy_card.id, Card.find(legacy_card.id).id
    assert_equal "fizzy-coexist-001", Card.find("fizzy-coexist-001").id

    # Both have valid String-typed ids per the post-widen schema
    assert_kind_of String, legacy_card.id
    assert_kind_of String, beads_card.id
  end
end
