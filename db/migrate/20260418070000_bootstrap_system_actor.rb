class BootstrapSystemActor < ActiveRecord::Migration[8.0]
  # S3 F.3 (fizzy-7j3): ensure SystemActor.identity + SystemActor.user exist
  # for every existing Account so jobs and poller attribution are reliable.
  #
  # Idempotent: safe to re-run.
  def up
    email = SystemActor.email

    identity = Identity.find_or_create_by!(email_address: email)

    Account.find_each do |account|
      user = User.where(account: account, role: :system).first_or_initialize
      user.identity = identity
      user.name = "Fizzy System"
      user.active = true if user.has_attribute?(:active)
      user.save! if user.changed?
    end
  end

  def down
    # Intentionally no-op. We do not delete users/identities since this is
    # install-time bootstrap data and may have become referenced.
  end
end

