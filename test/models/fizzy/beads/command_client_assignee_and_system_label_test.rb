require "test_helper"

# S5 F.4 (set_assignee) + S5 F.5 (_add_system_label / _remove_system_label).
class Fizzy::Beads::CommandClientAssigneeAndSystemLabelTest < ActiveSupport::TestCase
  setup do
    @client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")
    @ok_status = Struct.new(:success?, :exitstatus).new(true, 0)
  end

  # ---- set_assignee --------------------------------------------------

  test "set_assignee composes bd update --assignee with the email" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--assignee", "alice@example.com").returns([ "", "", @ok_status ])
    @client.set_assignee("fizzy-abc", "alice@example.com")
  end

  test "set_assignee passes empty string when email is nil (clears Beads assignee)" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--assignee", "").returns([ "", "", @ok_status ])
    @client.set_assignee("fizzy-abc", nil)
  end

  test "set_assignee passes empty string when email is empty (idempotent clear)" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--assignee", "").returns([ "", "", @ok_status ])
    @client.set_assignee("fizzy-abc", "")
  end

  # ---- _add_system_label / _remove_system_label ----------------------

  test "_add_system_label bypasses ReservedNamespace check (writes fizzy/ labels)" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--add-label", "fizzy/board/uuid-123").returns([ "", "", @ok_status ])
    @client._add_system_label("fizzy-abc", "fizzy/board/uuid-123")
  end

  test "_add_system_label still normalizes (downcase + strip)" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--add-label", "fizzy/board/abc").returns([ "", "", @ok_status ])
    @client._add_system_label("fizzy-abc", "  Fizzy/Board/ABC  ")
  end

  test "_remove_system_label removes fizzy/ labels (used by S2 board move)" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--remove-label", "fizzy/board/old-uuid").returns([ "", "", @ok_status ])
    @client._remove_system_label("fizzy-abc", "fizzy/board/old-uuid")
  end

  test "_add_system_label/_remove_system_label still raise on leading-#" do
    assert_raises(Fizzy::Beads::LabelNormalizer::InvalidLabelError) do
      @client._add_system_label("fizzy-abc", "#bad")
    end
    assert_raises(Fizzy::Beads::LabelNormalizer::InvalidLabelError) do
      @client._remove_system_label("fizzy-abc", "")
    end
  end
end
