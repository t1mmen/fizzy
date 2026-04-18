require "test_helper"

class AuthenticationCallbacksTest < ActiveSupport::TestCase
  test "Authentication sets set_current_actor after require_authentication" do
    before_filters =
      ApplicationController._process_action_callbacks
        .select { |callback| callback.kind == :before }
        .map(&:filter)

    assert_includes before_filters, :require_authentication
    assert_includes before_filters, :set_current_actor
    assert_operator before_filters.index(:require_authentication), :<, before_filters.index(:set_current_actor)
  end
end

