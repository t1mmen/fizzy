require "test_helper"
require "fizzy/beads/action_text_to_plaintext"

class Fizzy::Beads::ActionTextToPlaintextTest < ActiveSupport::TestCase
  test "returns empty string for blank input" do
    assert_equal "", Fizzy::Beads::ActionTextToPlaintext.call(nil)
    assert_equal "", Fizzy::Beads::ActionTextToPlaintext.call("")
  end

  test "preserves paragraph text" do
    html = "<div>Hello world</div>"
    assert_equal "Hello world", Fizzy::Beads::ActionTextToPlaintext.call(html)
  end

  test "preserves multi-paragraph text with double newlines" do
    html = "<div>First paragraph</div><div>Second paragraph</div>"
    result = Fizzy::Beads::ActionTextToPlaintext.call(html)
    assert_includes result, "First paragraph"
    assert_includes result, "Second paragraph"
  end

  test "accepts ActionText::Content directly" do
    content = ActionText::Content.new("<div>Direct content</div>")
    assert_equal "Direct content", Fizzy::Beads::ActionTextToPlaintext.call(content)
  end

  test "strips HTML formatting tags" do
    html = "<div><strong>Bold</strong> and <em>italic</em> text</div>"
    result = Fizzy::Beads::ActionTextToPlaintext.call(html)
    assert_includes result, "Bold"
    assert_includes result, "italic"
    assert_not_includes result, "<strong>"
    assert_not_includes result, "<em>"
  end

  test "drops inline action-text-attachment elements (S7 strip-on-write)" do
    html = "<div>Before <action-text-attachment sgid=\"abc\"></action-text-attachment> after</div>"
    result = Fizzy::Beads::ActionTextToPlaintext.call(html)
    assert_includes result, "Before"
    assert_includes result, "after"
    assert_not_includes result, "<action-text-attachment"
    assert_not_includes result, "sgid"
  end
end
