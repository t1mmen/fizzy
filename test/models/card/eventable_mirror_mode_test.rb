require "test_helper"

# S8 F.5: Card#touch_last_active_at must bypass callbacks when
# Current.beads_mirror? is true (poller-originated Event creation),
# but preserve update! semantics for normal request/job paths.
class Card::EventableMirrorModeTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    @card = cards(:logo)
    Current.beads_mirror = nil
  end

  teardown do
    Current.beads_mirror = nil
  end

  test "touch_last_active_at uses update! (callbacks fire) when mirror-mode is OFF" do
    assert_not Current.beads_mirror?

    # update! triggers Card's after_save / Searchable / etc. callbacks. We
    # assert that the standard AR write path is taken by checking that the
    # updated_at column also changes (update_columns would NOT touch updated_at).
    original_updated_at = @card.updated_at
    travel 1.second do
      @card.touch_last_active_at
    end
    assert_operator @card.reload.updated_at, :>, original_updated_at,
      "expected updated_at to advance under update! semantics"
  end

  test "touch_last_active_at uses update_columns (callbacks bypassed) when mirror-mode is ON" do
    Current.beads_mirror = true
    assert Current.beads_mirror?

    original_updated_at = @card.updated_at
    travel 2.seconds do
      @card.touch_last_active_at
    end
    # update_columns does NOT advance updated_at — that's the bypass signal.
    assert_equal original_updated_at.to_i, @card.reload.updated_at.to_i,
      "expected updated_at to NOT advance under update_columns bypass semantics"

    # last_active_at SHOULD still update (the operation succeeded).
    assert @card.last_active_at.present?
  end

  test "Current.beads_mirror? is falsy by default" do
    assert_not Current.beads_mirror?
  end

  test "Current.beads_mirror? is true when set to truthy value" do
    Current.beads_mirror = true
    assert Current.beads_mirror?
    Current.beads_mirror = "anything-truthy"
    assert Current.beads_mirror?
  end

  test "Current.beads_mirror? is false when set to nil/false" do
    Current.beads_mirror = false
    assert_not Current.beads_mirror?
    Current.beads_mirror = nil
    assert_not Current.beads_mirror?
  end

  test "Current.beads_mirror is per-thread (CurrentAttributes semantics)" do
    Current.beads_mirror = true
    Thread.new {
      assert_not Current.beads_mirror?, "different thread should not see this thread's mirror flag"
    }.join
  end
end
