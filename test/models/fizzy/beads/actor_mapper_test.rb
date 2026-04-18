require "test_helper"

class Fizzy::Beads::ActorMapperTest < ActiveSupport::TestCase
  setup do
    migrate_system_actor!
    @account = accounts(:"37s")
    @system_user = User.find_by!(account: @account, role: :system)
  end

  test "email match resolves Identity.user for the account" do
    actor = identities(:david).email_address
    assert_equal users(:david), Fizzy::Beads::ActorMapper.resolve(actor, account: @account)
  end

  test "unique name match resolves the User by name" do
    actor = users(:david).name
    assert_equal users(:david), Fizzy::Beads::ActorMapper.resolve(actor, account: @account)
  end

  test "ambiguous name falls back to the system user" do
    other_identity = Identity.create!(email_address: "other-actor@example.com")
    User.create!(
      account: @account,
      identity: other_identity,
      name: users(:david).name,
      role: :member,
      verified_at: Time.current
    )

    actor = users(:david).name
    assert_equal @system_user, Fizzy::Beads::ActorMapper.resolve(actor, account: @account)
  end

  test "unknown actor falls back to the system user" do
    assert_equal @system_user, Fizzy::Beads::ActorMapper.resolve("unknown actor", account: @account)
  end

  test "blank actor falls back to the system user" do
    assert_equal @system_user, Fizzy::Beads::ActorMapper.resolve("   ", account: @account)
  end

  private
    def migrate_system_actor!
      path = Rails.root.join("db/migrate/20260418070000_bootstrap_system_actor.rb")
      Object.send(:remove_const, :BootstrapSystemActor) if defined?(BootstrapSystemActor)
      load path
      BootstrapSystemActor.new.up
    end
end
