require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  setup do
    Current.account = nil
    Current.identity = nil
    Current.user = nil
    Current.actor = nil
  end

  test "identity= populates actor from Identity email_address" do
    Current.account = accounts(:"37s")
    Current.identity = identities(:david)

    assert_equal identities(:david).email_address, Current.actor
    assert_equal users(:david), Current.user
  end

  test "identity= clears actor when identity becomes nil" do
    Current.account = accounts(:"37s")
    Current.identity = identities(:david)
    assert_equal identities(:david).email_address, Current.actor

    Current.identity = nil
    assert_nil Current.actor
    assert_equal users(:david), Current.user
  end

  test "direct actor assignment works and is thread-local" do
    Current.actor = "main@example.com"

    thread_actor =
      Thread.new do
        Current.actor = "thread@example.com"
        Current.actor
      end.value

    assert_equal "thread@example.com", thread_actor
    assert_equal "main@example.com", Current.actor
  end

  test "Current.with restores actor after block" do
    Current.actor = "outside@example.com"

    Current.with(actor: "inside@example.com") do
      assert_equal "inside@example.com", Current.actor
    end

    assert_equal "outside@example.com", Current.actor
  end
end
