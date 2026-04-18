require "test_helper"
require "fizzy/beads/reserved_namespace"

class Fizzy::Beads::ReservedNamespaceTest < ActiveSupport::TestCase
  test "violates? returns true for fizzy/ prefix" do
    assert Fizzy::Beads::ReservedNamespace.violates?("fizzy/board/abc")
    assert Fizzy::Beads::ReservedNamespace.violates?("fizzy/system/foo")
    assert Fizzy::Beads::ReservedNamespace.violates?("fizzy/test/x")
  end

  test "violates? is case-insensitive after normalization" do
    assert Fizzy::Beads::ReservedNamespace.violates?("Fizzy/board/abc")
    assert Fizzy::Beads::ReservedNamespace.violates?("FIZZY/board/abc")
  end

  test "violates? returns false for unrelated labels" do
    assert_not Fizzy::Beads::ReservedNamespace.violates?("backend")
    assert_not Fizzy::Beads::ReservedNamespace.violates?("ui")
    assert_not Fizzy::Beads::ReservedNamespace.violates?("feature/auth")
  end

  test "violates? returns false for embedded fizzy/ (only leading reserved)" do
    assert_not Fizzy::Beads::ReservedNamespace.violates?("teamfizzy/foo")
    assert_not Fizzy::Beads::ReservedNamespace.violates?("project-fizzy/bar")
  end

  test "violates? returns false on empty/invalid input (LabelNormalizer raises, swallowed)" do
    assert_not Fizzy::Beads::ReservedNamespace.violates?("")
    assert_not Fizzy::Beads::ReservedNamespace.violates?("   ")
    assert_not Fizzy::Beads::ReservedNamespace.violates?("#hashtag")
  end

  test "violates? composes with LabelNormalizer (whitespace stripped first)" do
    assert Fizzy::Beads::ReservedNamespace.violates?("  fizzy/board/abc  ")
  end
end
