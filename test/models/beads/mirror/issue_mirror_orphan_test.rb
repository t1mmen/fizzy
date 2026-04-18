require "test_helper"

# S9 F.10 (fizzy-pmi.10): orphan cleanup hook in IssueMirror.call_by_id.
# When Beads source returns nil for an issue_id (i.e. the issue was
# hard-deleted via bd CLI), enqueue OrphanCleanupJob to remove the
# stale Card mirror row + cascade.
class Beads::Mirror::IssueMirrorOrphanTest < ActiveJob::TestCase
  setup do
    Current.session = sessions(:david)
    Rails.application.config.x.fizzy.install_hostname = "test.fizzy.localhost"
    @account = accounts("37s")
    @board = boards(:writebook)
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = nil
  end

  # Source stub used to test the find_issue → 404 path
  class FakeSource
    def initialize(issues_by_id: {})
      @issues = issues_by_id
    end

    def find_issue(id)
      @issues[id.to_s]
    end
  end

  test "call_by_id with source returning nil enqueues OrphanCleanupJob" do
    source = FakeSource.new(issues_by_id: {})

    assert_enqueued_with job: OrphanCleanupJob, args: [ "fizzy-orphan-x" ] do
      result = Beads::Mirror::IssueMirror.call_by_id(
        "fizzy-orphan-x",
        source: source,
        account_id: @account.id,
        board_id: @board.id,
        creator_id: users(:david).id
      )
      assert_nil result
    end
  end

  test "call_by_id with source returning an issue does NOT enqueue OrphanCleanupJob" do
    source = FakeSource.new(issues_by_id: {
      "fizzy-present-001" => { id: "fizzy-present-001", status: "open", title: "Present" }
    })

    assert_no_enqueued_jobs only: OrphanCleanupJob do
      Beads::Mirror::IssueMirror.call_by_id(
        "fizzy-present-001",
        source: source,
        account_id: @account.id,
        board_id: @board.id,
        creator_id: users(:david).id
      )
    end

    assert Card.exists?(id: "fizzy-present-001")
  end

  test "call_by_id replay against missing issue is idempotent (no raise; OrphanCleanupJob re-enqueued safely)" do
    source = FakeSource.new(issues_by_id: {})
    assert_nothing_raised do
      2.times do
        Beads::Mirror::IssueMirror.call_by_id(
          "fizzy-replay-001",
          source: source,
          account_id: @account.id,
          board_id: @board.id,
          creator_id: users(:david).id
        )
      end
    end
    assert_equal 2, enqueued_jobs.count { |j| j["job_class"] == "OrphanCleanupJob" }
  end

  test "call_by_id with empty/blank issue_id is a no-op" do
    source = FakeSource.new(issues_by_id: {})

    assert_no_enqueued_jobs only: OrphanCleanupJob do
      assert_nil Beads::Mirror::IssueMirror.call_by_id("", source: source, account_id: @account.id, board_id: @board.id)
      assert_nil Beads::Mirror::IssueMirror.call_by_id(nil, source: source, account_id: @account.id, board_id: @board.id)
    end
  end

  test "call_by_id with source that doesn't respond to find_issue treats as 404" do
    source = Object.new  # bare object — doesn't respond to find_issue

    assert_enqueued_with job: OrphanCleanupJob, args: [ "fizzy-no-source-method" ] do
      Beads::Mirror::IssueMirror.call_by_id(
        "fizzy-no-source-method",
        source: source,
        account_id: @account.id,
        board_id: @board.id
      )
    end
  end
end
