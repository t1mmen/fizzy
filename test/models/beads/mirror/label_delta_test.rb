require "test_helper"

# S9 F.5 (fizzy-pmi.5): callback-bypass label delta procedure.
class Beads::Mirror::LabelDeltaTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    @account = accounts("37s")
    @card_id = "fizzy-test-label-001"
    Beads::Mirror::IssueMirror.call(
      { id: @card_id, status: "open", title: "Label test" },
      account_id: @account.id,
      board_id: boards(:writebook).id,
      creator_id: users(:david).id
    )
  end

  test "apply :added creates Tag + Tagging when neither exists" do
    assert_difference [ "Tag.count", "Tagging.count" ], 1 do
      Beads::Mirror::LabelDelta.apply(
        operation: :added,
        account_id: @account.id,
        card_id: @card_id,
        label: "backend"
      )
    end
  end

  test "apply :added is idempotent (re-running same delta does NOT duplicate)" do
    Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: @card_id, label: "ui")
    assert_no_difference [ "Tag.count", "Tagging.count" ] do
      Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: @card_id, label: "ui")
    end
  end

  test "apply :added normalizes label (downcase + strip)" do
    Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: @card_id, label: "  Backend  ")
    # Tag model normalizes on read, so query by the canonical form.
    # Verify the actual stored value via raw SQL to confirm normalization
    # happens at the LabelDelta layer (not just at Tag's read-side).
    raw_titles = Tag.where(account_id: @account.id).pluck(:title)
    assert_includes raw_titles, "backend"
    assert_not_includes raw_titles, "Backend"
    assert_not_includes raw_titles, "  Backend  "
  end

  test "apply :added silently skips invalid labels (Beads-only #-prefixed per S5 §E.4)" do
    assert_no_difference [ "Tag.count", "Tagging.count" ] do
      Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: @card_id, label: "#Backend")
    end
  end

  test "apply :added silently skips empty labels" do
    assert_no_difference [ "Tag.count", "Tagging.count" ] do
      Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: @card_id, label: "")
    end
  end

  test "apply :removed deletes Tagging but preserves Tag" do
    Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: @card_id, label: "removeme")
    assert Tag.exists?(account_id: @account.id, title: "removeme")

    assert_difference "Tagging.count", -1 do
      assert_no_difference "Tag.count" do
        Beads::Mirror::LabelDelta.apply(operation: :removed, account_id: @account.id, card_id: @card_id, label: "removeme")
      end
    end
  end

  test "apply :removed is no-op when tag doesn't exist for the account" do
    assert_no_difference [ "Tag.count", "Tagging.count" ] do
      Beads::Mirror::LabelDelta.apply(operation: :removed, account_id: @account.id, card_id: @card_id, label: "never_existed")
    end
  end

  test "apply :removed only affects the matching (card_id, tag_id), not other cards' taggings" do
    other_card_id = "fizzy-test-label-002"
    Beads::Mirror::IssueMirror.call(
      { id: other_card_id, status: "open", title: "Other" },
      account_id: @account.id, board_id: boards(:writebook).id, creator_id: users(:david).id
    )
    Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: @card_id, label: "shared")
    Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: other_card_id, label: "shared")

    assert_difference "Tagging.count", -1 do
      Beads::Mirror::LabelDelta.apply(operation: :removed, account_id: @account.id, card_id: @card_id, label: "shared")
    end
    # other_card still has the tagging
    assert Tagging.where(card_id: other_card_id).joins(:tag).where(tags: { title: "shared" }).exists?
  end

  test "unknown operation logs warning and is a no-op" do
    assert_no_difference [ "Tag.count", "Tagging.count" ] do
      Beads::Mirror::LabelDelta.apply(operation: :weird, account_id: @account.id, card_id: @card_id, label: "x")
    end
  end

  test "system labels (fizzy/board/<uuid>) are mirrored normally (poller writes them; UI reject is controller-side)" do
    Beads::Mirror::LabelDelta.apply(operation: :added, account_id: @account.id, card_id: @card_id, label: "fizzy/board/abc")
    assert Tag.exists?(account_id: @account.id, title: "fizzy/board/abc"),
      "poller must mirror reserved system labels; namespace policy is enforced at controller layer only (S5 §D.2)"
  end
end
