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
  end

  test "identity= clears actor when identity becomes nil" do
    Current.account = accounts(:"37s")
    Current.identity = identities(:david)
    assert_equal identities(:david).email_address, Current.actor

    Current.identity = nil
    assert_nil Current.actor
  end
end
