require "test_helper"

# S5 F.3: CommandClient label methods (add_label / remove_label / set_labels).
# Tests argv composition, normalization (LabelNormalizer), and reserved
# fizzy/ namespace rejection (ReservedNamespace).
class Fizzy::Beads::CommandClientLabelMethodsTest < ActiveSupport::TestCase
  setup do
    @client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")
    @ok_status = Struct.new(:success?, :exitstatus).new(true, 0)
  end

  # ---- add_label -----------------------------------------------------

  test "add_label composes bd update --add-label argv with normalized label" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--add-label", "backend").returns([ "", "", @ok_status ])
    @client.add_label("fizzy-abc", "Backend")
  end

  test "add_label strips whitespace and downcases via LabelNormalizer" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--add-label", "ui-bug").returns([ "", "", @ok_status ])
    @client.add_label("fizzy-abc", "  UI-Bug  ")
  end

  test "add_label raises ArgumentError on reserved fizzy/ namespace" do
    error = assert_raises(ArgumentError) do
      @client.add_label("fizzy-abc", "fizzy/board/some-uuid")
    end
    assert_match(/reserved namespace/i, error.message)
  end

  test "add_label raises InvalidLabelError on leading-#" do
    assert_raises(Fizzy::Beads::LabelNormalizer::InvalidLabelError) do
      @client.add_label("fizzy-abc", "#hashtag")
    end
  end

  # ---- remove_label --------------------------------------------------

  test "remove_label composes bd update --remove-label argv with normalized label" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--remove-label", "backend").returns([ "", "", @ok_status ])
    @client.remove_label("fizzy-abc", "Backend")
  end

  test "remove_label is symmetric to add_label (no namespace reject — system code may want to remove fizzy/ labels)" do
    # remove_label intentionally does NOT enforce ReservedNamespace because
    # _remove_system_label (S5 F.5) is the named system path, but generic
    # remove on a stale fizzy/ label should still be possible.
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--remove-label", "fizzy/board/old-uuid").returns([ "", "", @ok_status ])
    @client.remove_label("fizzy-abc", "fizzy/board/old-uuid")
  end

  # ---- set_labels ----------------------------------------------------

  test "set_labels composes bd update --set-labels with comma-joined normalized labels" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--set-labels", "backend,ui-bug").returns([ "", "", @ok_status ])
    @client.set_labels("fizzy-abc", [ "Backend", "UI-Bug" ])
  end

  test "set_labels rejects ANY label in reserved fizzy/ namespace" do
    error = assert_raises(ArgumentError) do
      @client.set_labels("fizzy-abc", [ "backend", "fizzy/board/uuid" ])
    end
    assert_match(/reserved namespace/i, error.message)
  end

  test "set_labels accepts a single label as array" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--set-labels", "backend").returns([ "", "", @ok_status ])
    @client.set_labels("fizzy-abc", [ "backend" ])
  end

  test "set_labels handles non-array input by wrapping in Array" do
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--set-labels", "backend").returns([ "", "", @ok_status ])
    @client.set_labels("fizzy-abc", "backend")
  end
end
