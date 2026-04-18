require "test_helper"
require "fizzy/beads/label_normalizer"

class Fizzy::Beads::LabelNormalizerTest < ActiveSupport::TestCase
  test "downcases input" do
    assert_equal "backend", Fizzy::Beads::LabelNormalizer.call("Backend")
    assert_equal "feature/auth", Fizzy::Beads::LabelNormalizer.call("Feature/AUTH")
  end

  test "strips surrounding whitespace" do
    assert_equal "backend", Fizzy::Beads::LabelNormalizer.call("  backend  ")
    assert_equal "ui", Fizzy::Beads::LabelNormalizer.call("\tui\n")
  end

  test "raises InvalidLabelError on leading #" do
    assert_raises(Fizzy::Beads::LabelNormalizer::InvalidLabelError) do
      Fizzy::Beads::LabelNormalizer.call("#hashtag")
    end
  end

  test "raises InvalidLabelError on leading # after whitespace strip" do
    assert_raises(Fizzy::Beads::LabelNormalizer::InvalidLabelError) do
      Fizzy::Beads::LabelNormalizer.call("  #leading-hash  ")
    end
  end

  test "raises InvalidLabelError on empty input" do
    assert_raises(Fizzy::Beads::LabelNormalizer::InvalidLabelError) do
      Fizzy::Beads::LabelNormalizer.call("")
    end
  end

  test "raises InvalidLabelError on whitespace-only input" do
    assert_raises(Fizzy::Beads::LabelNormalizer::InvalidLabelError) do
      Fizzy::Beads::LabelNormalizer.call("   ")
    end
  end

  test "raises InvalidLabelError on nil-equivalent input" do
    assert_raises(Fizzy::Beads::LabelNormalizer::InvalidLabelError) do
      Fizzy::Beads::LabelNormalizer.call(nil)
    end
  end

  test "preserves slashes (used by reserved namespace)" do
    assert_equal "fizzy/board/abc123", Fizzy::Beads::LabelNormalizer.call("Fizzy/Board/abc123")
  end
end
