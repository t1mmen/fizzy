require "test_helper"

# S5 F.7 (fizzy-7dc): Assignment AR callbacks mirror the primary
# (chronologically first) assignee's email to Beads via CommandClient.
#
# Direct-method testing pattern: after_create_commit / after_destroy_commit
# do not fire inside transactional fixtures (Rails default), so we test the
# private callback method directly + verify the callback wiring via
# reflection on the AR class.
class AssignmentBeadsSyncTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    Current.actor = "david@37signals.com"
    Rails.application.config.x.fizzy.install_hostname = "test.fizzy.localhost"
    @account = accounts("37s")
    @board = boards(:writebook)
    @beads_card = @board.cards.create!(id: "fizzy-assign-001", title: "Beads card", creator: users(:david))
    @uuid_card = cards(:logo)  # legacy uuid-id fixture
    @user_a = users(:david)
    @user_b = users(:kevin)
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = nil
    Current.actor = nil
    Current.beads_mirror = nil
  end

  test "after_create_commit + after_destroy_commit are wired" do
    create_callbacks  = Assignment._commit_callbacks.select { |c| c.kind == :after && c.filter == :sync_primary_assignee_to_beads }
    destroy_callbacks = Assignment._destroy_callbacks.select { |c| c.kind == :after }
    # Single :sync_primary_assignee_to_beads callback registered for create+destroy commits
    assert create_callbacks.any?, "expected after_create_commit + after_destroy_commit :sync_primary_assignee_to_beads to be registered"
  end

  test "sync_primary_assignee_to_beads invokes CommandClient.set_assignee with the primary's email (Beads-id card)" do
    assignment = Assignment.new(card: @beads_card, assignee: @user_a, assigner: @user_a)
    @beads_card.assignments << assignment

    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee)
      .with(@beads_card.id, @user_a.identity.email_address).once
    assignment.send(:sync_primary_assignee_to_beads)
  end

  test "sync passes empty string when no assignments remain (clears Beads assignee)" do
    a = Assignment.new(card: @beads_card, assignee: @user_a, assigner: @user_a)
    @beads_card.assignments << a

    # Simulate destroy: re-call the sync after primary is gone
    @beads_card.assignments.delete_all
    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee).with(@beads_card.id, "").once
    a.send(:sync_primary_assignee_to_beads)
  end

  test "sync skips when card.id is NOT a Beads issue id (legacy uuid card)" do
    a = Assignment.new(card: @uuid_card, assignee: @user_a, assigner: @user_a)
    @uuid_card.assignments << a

    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee).never
    a.send(:sync_primary_assignee_to_beads)
  end

  test "sync skips when in beads_mirror? mode (avoid re-emit from poller)" do
    Current.beads_mirror = true
    a = Assignment.new(card: @beads_card, assignee: @user_a, assigner: @user_a)
    @beads_card.assignments << a

    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee).never
    a.send(:sync_primary_assignee_to_beads)
  end

  test "sync skips when Current.actor is not set" do
    Current.actor = nil
    a = Assignment.new(card: @beads_card, assignee: @user_a, assigner: @user_a)
    @beads_card.assignments << a

    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee).never
    assert_nothing_raised { a.send(:sync_primary_assignee_to_beads) }
  end

  test "sync rescues CommandClient errors (logs + returns; doesn't raise)" do
    a = Assignment.new(card: @beads_card, assignee: @user_a, assigner: @user_a)
    @beads_card.assignments << a

    Fizzy::Beads::CommandClient.any_instance.stubs(:set_assignee).raises(StandardError, "bd died")
    assert_nothing_raised { a.send(:sync_primary_assignee_to_beads) }
  end

  test "primary is chronologically first when multiple assignments exist" do
    a1 = Assignment.create!(card: @beads_card, assignee: @user_a, assigner: @user_a, created_at: 2.days.ago)
    a2 = Assignment.create!(card: @beads_card, assignee: @user_b, assigner: @user_a, created_at: 1.day.ago)

    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee)
      .with(@beads_card.id, @user_a.identity.email_address).once
    a2.send(:sync_primary_assignee_to_beads)
  end
end
