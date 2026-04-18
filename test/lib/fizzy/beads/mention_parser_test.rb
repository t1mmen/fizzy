require "test_helper"

class Fizzy::Beads::MentionParserTest < ActiveSupport::TestCase
  setup do
    @mentionable_users = [ users(:david), users(:jz), users(:kevin) ]
  end

  test "extracts @email mentions" do
    text = "Hi @jz@37signals.com, please look"
    mentionees = Fizzy::Beads::MentionParser.call(text, mentionable_users: @mentionable_users)

    assert_equal [ users(:jz) ], mentionees
  end

  test "extracts @handle mentions (unique handle match)" do
    text = "Hi @david, please look"
    mentionees = Fizzy::Beads::MentionParser.call(text, mentionable_users: @mentionable_users)

    assert_equal [ users(:david) ], mentionees
  end

  test "ignores unknown users" do
    text = "Hi @nobody@example.com"
    mentionees = Fizzy::Beads::MentionParser.call(text, mentionable_users: @mentionable_users)

    assert_empty mentionees
  end

  test "ignores ambiguous handle matches" do
    # Both system users share the name "System" which yields identical handles.
    ambiguous_users = [ users(:system), users(:system_initech) ]
    text = "Hi @system"

    mentionees = Fizzy::Beads::MentionParser.call(text, mentionable_users: ambiguous_users)
    assert_empty mentionees
  end
end

