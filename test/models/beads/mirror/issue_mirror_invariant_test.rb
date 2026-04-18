require "test_helper"

# S9 F.9 (fizzy-pmi.9): single-board invariant correction in mirror_issue.
# Per S2 §G.2: cards must have at most ONE fizzy/board/<uuid> label.
# The poller corrects via CommandClient (system actor) — deterministic
# + idempotent so subsequent ticks don't loop.
class Beads::Mirror::IssueMirrorInvariantTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    Rails.application.config.x.fizzy.install_hostname = "test.fizzy.localhost"
    @account = accounts("37s")
    @board = boards(:writebook)
    # Stub the system actor identity lookup so tests don't need the
    # full SystemActor migration (fizzy-7j3) applied to the test fixture.
    @system_identity = identities(:david)
    SystemActor.stubs(:identity).returns(@system_identity)
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = nil
  end

  test "single board label triggers no correction" do
    Fizzy::Beads::CommandClient.any_instance.expects(:_remove_system_label).never
    issue = {
      id: "fizzy-inv-001",
      status: "open",
      title: "Single board",
      labels: [ "fizzy/board/uuid-A" ]
    }
    Beads::Mirror::IssueMirror.call(issue, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
  end

  test "zero board labels triggers no correction" do
    Fizzy::Beads::CommandClient.any_instance.expects(:_remove_system_label).never
    issue = {
      id: "fizzy-inv-002",
      status: "open",
      title: "No boards",
      labels: [ "backend", "ui" ]
    }
    Beads::Mirror::IssueMirror.call(issue, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
  end

  test "two board labels triggers exactly N-1 = 1 remove_label invocation" do
    issue = {
      id: "fizzy-inv-003",
      status: "open",
      title: "Two boards",
      labels: [ "fizzy/board/uuid-B", "fizzy/board/uuid-A", "backend" ]
    }
    # Lexicographic min is "fizzy/board/uuid-A" — keep that, remove uuid-B
    Fizzy::Beads::CommandClient.any_instance.expects(:_remove_system_label)
      .with("fizzy-inv-003", "fizzy/board/uuid-B").once
    Beads::Mirror::IssueMirror.call(issue, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
  end

  test "three board labels triggers N-1 = 2 remove_label invocations" do
    issue = {
      id: "fizzy-inv-004",
      status: "open",
      title: "Three boards",
      labels: [ "fizzy/board/uuid-C", "fizzy/board/uuid-A", "fizzy/board/uuid-B" ]
    }
    Fizzy::Beads::CommandClient.any_instance.expects(:_remove_system_label).twice
    Beads::Mirror::IssueMirror.call(issue, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
  end

  test "deterministic keep: lexicographically smallest uuid wins (default override returns nil)" do
    issue = {
      id: "fizzy-inv-005",
      status: "open",
      title: "Deterministic",
      labels: [ "fizzy/board/zzzz", "fizzy/board/aaaa", "fizzy/board/mmmm" ]
    }
    Fizzy::Beads::CommandClient.any_instance.expects(:_remove_system_label)
      .with("fizzy-inv-005", "fizzy/board/zzzz").once
    Fizzy::Beads::CommandClient.any_instance.expects(:_remove_system_label)
      .with("fizzy-inv-005", "fizzy/board/mmmm").once
    Beads::Mirror::IssueMirror.call(issue, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
  end

  test "read_most_recent_board_label_event override is honored when it returns a present label" do
    issue = {
      id: "fizzy-inv-006",
      status: "open",
      title: "Event-ordered keep",
      labels: [ "fizzy/board/uuid-A", "fizzy/board/uuid-B" ]
    }
    # Override the hook: prefer the LATER label (uuid-B), so uuid-A gets removed
    Beads::Mirror::IssueMirror.stubs(:read_most_recent_board_label_event).returns("fizzy/board/uuid-B")
    Fizzy::Beads::CommandClient.any_instance.expects(:_remove_system_label)
      .with("fizzy-inv-006", "fizzy/board/uuid-A").once
    Beads::Mirror::IssueMirror.call(issue, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
  end

  test "labels can be read from a Struct (duck-typed responds_to :labels)" do
    issue_struct = Struct.new(:id, :status, :title, :closed_at, :defer_until, :close_reason, :metadata, :labels, keyword_init: true)
    issue = issue_struct.new(
      id: "fizzy-inv-007", status: "open", title: "Struct labels",
      closed_at: nil, defer_until: nil, close_reason: nil, metadata: nil,
      labels: [ "fizzy/board/aaa", "fizzy/board/bbb" ]
    )
    Fizzy::Beads::CommandClient.any_instance.expects(:_remove_system_label)
      .with("fizzy-inv-007", "fizzy/board/bbb").once
    Beads::Mirror::IssueMirror.call(issue, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
  end

  test "errors during corrective remove_label are logged but do not raise" do
    issue = {
      id: "fizzy-inv-008",
      status: "open",
      title: "Error handling",
      labels: [ "fizzy/board/aaa", "fizzy/board/bbb" ]
    }
    Fizzy::Beads::CommandClient.any_instance.stubs(:_remove_system_label).raises(StandardError, "bd died")
    assert_nothing_raised do
      Beads::Mirror::IssueMirror.call(issue, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
    end
  end

  test "idempotency: re-running mirror_issue post-correction (single label) triggers no further calls" do
    issue_pre = {
      id: "fizzy-inv-009",
      status: "open",
      title: "Idempotent",
      labels: [ "fizzy/board/aaa", "fizzy/board/bbb" ]
    }
    Fizzy::Beads::CommandClient.any_instance.stubs(:_remove_system_label)
    Beads::Mirror::IssueMirror.call(issue_pre, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)

    # Second tick: only 1 board label remains in the fresh source data
    issue_post = issue_pre.merge(labels: [ "fizzy/board/aaa" ])
    Fizzy::Beads::CommandClient.any_instance.expects(:_remove_system_label).never
    Beads::Mirror::IssueMirror.call(issue_post, account_id: @account.id, board_id: @board.id, creator_id: users(:david).id)
  end
end
