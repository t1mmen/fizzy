require "test_helper"

# S7 F.6 (fizzy-nid): cleanup job for Card mirror rows whose Beads
# parent has been hard-deleted (rare in V1; CLI-driven).
class OrphanCleanupJobTest < ActiveJob::TestCase
  setup do
    Current.session = sessions(:david)
    Current.request_id = "test-orphan-cleanup"
    @account = accounts("37s")
    @board = boards(:writebook)
  end

  test "perform destroys the Card mirror row when given a known id" do
    card = @board.cards.create!(id: "fizzy-orphan-001", title: "To be cleaned")
    assert Card.exists?(id: "fizzy-orphan-001")

    OrphanCleanupJob.perform_now("fizzy-orphan-001")

    assert_not Card.exists?(id: "fizzy-orphan-001")
  end

  test "perform is a no-op when the Card has already been cleaned up (idempotent)" do
    assert_nothing_raised do
      OrphanCleanupJob.perform_now("fizzy-never-existed")
    end
  end

  test "perform suppresses Storage::Entry recording during cascade" do
    card = @board.cards.create!(id: "fizzy-orphan-002", title: "With attachment")
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("x" * 256), filename: "x.txt", content_type: "text/plain")
    card.update!(description: "<p>#{ActionText::Attachment.from_attachable(blob).to_html}</p>")

    # Capture entry count before cleanup
    entries_before = Storage::Entry.where(account_id: @account.id).count

    OrphanCleanupJob.perform_now("fizzy-orphan-002")

    # No new "detach" entry rows from the cascade (suppressing_recording active)
    entries_after = Storage::Entry.where(account_id: @account.id).count
    assert_equal entries_before, entries_after,
      "expected Storage::Entry recording to be suppressed during orphan cleanup"
  end

  test "perform cascades dependent: :destroy chains (rich_text + attachments removed)" do
    card = @board.cards.create!(id: "fizzy-orphan-003", title: "Cascade test")
    card.update!(description: "<p>some content</p>")
    rich_text_id = card.rich_text_description.id

    OrphanCleanupJob.perform_now("fizzy-orphan-003")

    assert_not Card.exists?(id: "fizzy-orphan-003")
    assert_not ActionText::RichText.exists?(id: rich_text_id),
      "expected dependent: :destroy chain to remove the rich_text"
  end

  test "perform accepts string or symbol issue_id (Beads-style varchar input)" do
    @board.cards.create!(id: "fizzy-orphan-str", title: "x")
    OrphanCleanupJob.perform_now("fizzy-orphan-str")
    assert_not Card.exists?(id: "fizzy-orphan-str")
  end

  test "perform_later enqueues the job for async execution" do
    assert_enqueued_with job: OrphanCleanupJob, args: [ "fizzy-orphan-async" ] do
      OrphanCleanupJob.perform_later("fizzy-orphan-async")
    end
  end
end
