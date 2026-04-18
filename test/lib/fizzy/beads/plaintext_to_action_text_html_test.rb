require "test_helper"
require "fizzy/beads/plaintext_to_action_text_html"

class Fizzy::Beads::PlaintextToActionTextHtmlTest < ActiveSupport::TestCase
  test "returns empty string for blank input" do
    assert_equal "", Fizzy::Beads::PlaintextToActionTextHtml.call(nil)
    assert_equal "", Fizzy::Beads::PlaintextToActionTextHtml.call("")
  end

  test "wraps single line in <p>" do
    result = Fizzy::Beads::PlaintextToActionTextHtml.call("Hello world")
    assert_equal "<p>Hello world</p>", result
  end

  test "wraps multi-paragraph (double newline) in separate <p> tags" do
    result = Fizzy::Beads::PlaintextToActionTextHtml.call("First\n\nSecond")
    assert_includes result, "<p>First</p>"
    assert_includes result, "<p>Second</p>"
  end

  test "converts single newlines within a paragraph to <br>" do
    result = Fizzy::Beads::PlaintextToActionTextHtml.call("Line one\nLine two")
    assert_includes result, "Line one"
    assert_includes result, "<br"
    assert_includes result, "Line two"
  end

  test "escapes HTML to prevent XSS" do
    result = Fizzy::Beads::PlaintextToActionTextHtml.call("<script>alert('xss')</script>")
    assert_not_includes result, "<script>"
    assert_includes result, "&lt;script&gt;"
  end

  test "escapes ampersands and quotes" do
    result = Fizzy::Beads::PlaintextToActionTextHtml.call("foo & bar \"quoted\"")
    assert_includes result, "&amp;"
  end

  test "no inline attachments (S7 §C — never reconstructed from plaintext)" do
    result = Fizzy::Beads::PlaintextToActionTextHtml.call("Some text without markup")
    assert_not_includes result, "action-text-attachment"
    assert_not_includes result, "sgid"
  end
end
