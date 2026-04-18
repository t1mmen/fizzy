require "test_helper"

# S5 F.10 (fizzy-jig): integration test for AssignmentsController + Beads
# sync. Verifies the full controller → Card#toggle_assignment → AR
# assignments → after_create_commit → CommandClient.set_assignee path.
class Cards::AssignmentsFlowTest < ActionDispatch::IntegrationTest
  # Disable transactional fixtures so after_create_commit fires.
  self.use_transactional_tests = false

  setup do
    sign_in_as :david
    Rails.application.config.x.fizzy.install_hostname = "test.fizzy.localhost"

    @account = accounts("37s")
    @board = boards(:writebook)
    # Create a Beads-id card so the sync callback fires (uuid cards are skipped per fizzy-7dc).
    # Unique-per-test id avoids cross-test collisions under use_transactional_tests = false.
    @card_id = "fizzy-jig-#{SecureRandom.hex(4)}"
    @beads_card = @board.cards.create!(id: @card_id, title: "Beads card", creator: users(:david))
    # S2: make the Beads-id card accessible via label-based board membership.
    tag = Tag.find_or_create_by!(account: @board.account, title: @board.membership_label)
    Tagging.find_or_create_by!(account: @board.account, card: @beads_card, tag: tag)
    @user_a = users(:david)
    @user_b = users(:kevin)
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = nil
    # Card#destroy cascades to assignments/events/comments/etc. via dependent: associations.
    # Without this, leftover Event/Notification rows referencing the card would fail on FK delete.
    if @card_id
      Card.find_by(id: @card_id)&.destroy
      # Also clean up any uuid-card assignments created by the legacy-skip test.
      Assignment.where(assignee_id: [ @user_a&.id, @user_b&.id ].compact, card_id: cards(:logo).id).delete_all
    end
  end

  test "POST creates Assignment + invokes CommandClient.set_assignee with primary email" do
    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee)
      .with(@beads_card.id, @user_a.identity.email_address).once

    assert_difference "Assignment.count", 1 do
      post(
        "/#{@account.external_account_id}/cards/#{@beads_card.number}/assignments",
        params: { assignee_id: @user_a.id },
        as: :turbo_stream
      )
    end
    assert_response :success
  end

  test "DELETE (toggle off via POST) destroys Assignment + invokes set_assignee with empty string when last" do
    @beads_card.assignments.create!(assignee: @user_a, assigner: @user_a)

    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee)
      .with(@beads_card.id, "").once

    assert_difference "Assignment.count", -1 do
      # toggle: same assignee_id removes the assignment
      post(
        "/#{@account.external_account_id}/cards/#{@beads_card.number}/assignments",
        params: { assignee_id: @user_a.id },
        as: :turbo_stream
      )
    end
    assert_response :success
  end

  test "removing primary promotes next-oldest as primary (chronological order)" do
    @beads_card.assignments.create!(assignee: @user_a, assigner: @user_a, created_at: 2.days.ago)
    @beads_card.assignments.create!(assignee: @user_b, assigner: @user_a, created_at: 1.day.ago)

    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee)
      .with(@beads_card.id, @user_b.identity.email_address).once

    assert_difference "Assignment.count", -1 do
      post(
        "/#{@account.external_account_id}/cards/#{@beads_card.number}/assignments",
        params: { assignee_id: @user_a.id },
        as: :turbo_stream
      )
    end
  end

  test "uuid-id Card flow does NOT shell out to CommandClient (legacy cards skipped per fizzy-7dc)" do
    uuid_card = cards(:logo)
    Fizzy::Beads::CommandClient.any_instance.expects(:set_assignee).never

    post(
      "/#{@account.external_account_id}/cards/#{uuid_card.number}/assignments",
      params: { assignee_id: @user_b.id },
      as: :turbo_stream
    )
    assert_response :success
  end
end
