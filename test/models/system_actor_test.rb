require "test_helper"

class SystemActorTest < ActiveSupport::TestCase
  setup do
    SystemActor.instance_variable_set(:@user, nil)

    @identity = Identity.find_or_create_by!(email_address: SystemActor.email)
    @identity.users.find_or_create_by!(account: accounts(:"37s"), role: :system) do |user|
      user.name = "Fizzy System"
    end
  end

  test "email uses the configured install hostname" do
    assert_equal "system@app.fizzy.localhost", SystemActor.email
  end

  test "identity resolves the singleton system Identity row" do
    assert_equal @identity, SystemActor.identity
  end

  test "user resolves the system User for that Identity" do
    assert_equal :system, SystemActor.user.role.to_sym
    assert_equal @identity, SystemActor.user.identity
  end

  test "install_hostname raises with a clear error when missing" do
    previous = Rails.application.config.x.fizzy.install_hostname
    Rails.application.config.x.fizzy.install_hostname = nil
    SystemActor.instance_variable_set(:@user, nil)

    error = assert_raises(RuntimeError) { SystemActor.install_hostname }
    assert_match(/install_hostname is not set/, error.message)
  ensure
    Rails.application.config.x.fizzy.install_hostname = previous
  end
end

