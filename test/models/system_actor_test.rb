require "test_helper"

class SystemActorTest < ActiveSupport::TestCase
  setup do
    SystemActor.instance_variable_set(:@user, nil)
    migrate_system_actor!
    @identity = SystemActor.identity
  end

  test "email uses the configured install hostname" do
    assert_equal "system@app.fizzy.localhost", SystemActor.email
  end

  test "identity resolves the singleton system Identity row" do
    assert_equal @identity, SystemActor.identity
  end

  test "user resolves the system User for that Identity" do
    system_user = User.find_by!(account: accounts(:"37s"), role: :system, identity: @identity)
    assert_equal :system, system_user.role.to_sym
    assert_equal "Fizzy System", system_user.name
    assert_equal @identity, system_user.identity
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

  private
    def migrate_system_actor!
      path = Rails.root.join("db/migrate/20260418070000_bootstrap_system_actor.rb")
      Object.send(:remove_const, :BootstrapSystemActor) if defined?(BootstrapSystemActor)
      load path
      BootstrapSystemActor.new.up
    end
end
