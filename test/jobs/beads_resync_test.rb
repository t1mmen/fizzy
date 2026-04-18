require "test_helper"

# S9 F.8 (fizzy-pmi.8): periodic full-sweep resync.
class BeadsResyncTest < ActiveJob::TestCase
  setup do
    Current.session = sessions(:david)
    Rails.application.config.x.fizzy.install_hostname = "test.fizzy.localhost"
    @account = accounts("37s")
    @board = boards(:writebook)
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = nil
  end

  # Source stub used to inject Beads-SQL-shaped data into the resync.
  class FakeSource
    attr_accessor :open_issues, :labels_by_issue, :custom_statuses

    def initialize(open_issues: [], labels_by_issue: {}, custom_statuses: [])
      @open_issues = open_issues
      @labels_by_issue = labels_by_issue
      @custom_statuses = custom_statuses
    end

    def labels_for(issue_id)
      @labels_by_issue[issue_id] || []
    end
  end

  test "perform with NullSource is a no-op (no errors)" do
    assert_nothing_raised do
      BeadsResync.perform_now
    end
  end

  test "perform with open issues mirrors each into Card via IssueMirror" do
    source = FakeSource.new(open_issues: [
      { id: "fizzy-resync-001", status: "open", title: "First" },
      { id: "fizzy-resync-002", status: "in_progress", title: "Second" }
    ])

    assert_difference "Card.count", 2 do
      BeadsResync.perform_now(source: source, account_id: @account.id, board_id: @board.id)
    end

    assert Card.exists?(id: "fizzy-resync-001")
    assert Card.exists?(id: "fizzy-resync-002")
  end

  test "perform with labels syncs adds + removes via LabelDelta" do
    Beads::Mirror::IssueMirror.call(
      { id: "fizzy-resync-003", status: "open", title: "Pre-tagged" },
      account_id: @account.id, board_id: @board.id, creator_id: users(:david).id
    )
    Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: "fizzy-resync-003", label: "stale")

    source = FakeSource.new(
      open_issues: [ { id: "fizzy-resync-003", status: "open", title: "Pre-tagged" } ],
      labels_by_issue: { "fizzy-resync-003" => [ "fresh" ] }
    )

    BeadsResync.perform_now(source: source, account_id: @account.id, board_id: @board.id)

    titles = Tagging.joins(:tag).where(card_id: "fizzy-resync-003").pluck("tags.title")
    assert_includes titles, "fresh", "expected to add label that exists in Beads but not mirror"
    assert_not_includes titles, "stale", "expected to remove label that no longer exists in Beads"
  end

  test "perform refreshes custom_statuses" do
    source = FakeSource.new(custom_statuses: [
      { name: "in_review", category: "unspecified" },
      { name: "frosted", category: "frozen" }
    ])

    BeadsResync.perform_now(source: source, account_id: @account.id, board_id: @board.id)

    assert Beads::CustomStatus.exists?(name: "in_review")
    assert Beads::CustomStatus.exists?(name: "frosted")
  end

  test "perform sets Current.beads_mirror during execution" do
    captured_mirror = nil
    BeadsResync.any_instance.stubs(:sweep_issues).with do |_|
      captured_mirror = Current.beads_mirror?
      true
    end.returns(nil)
    BeadsResync.any_instance.stubs(:sweep_custom_statuses).returns(nil)

    BeadsResync.perform_now(source: FakeSource.new)

    assert_equal true, captured_mirror
  end

  test "perform isolates per-issue errors (one bad issue does not abort sweep)" do
    source = FakeSource.new(open_issues: [
      { id: "fizzy-good-1", status: "open", title: "Good 1" },
      { id: nil, status: "open", title: "Bad — nil id" },  # blank id triggers IssueMirror skip
      { id: "fizzy-good-2", status: "open", title: "Good 2" }
    ])

    assert_nothing_raised do
      BeadsResync.perform_now(source: source, account_id: @account.id, board_id: @board.id)
    end

    assert Card.exists?(id: "fizzy-good-1")
    assert Card.exists?(id: "fizzy-good-2")
  end
end
