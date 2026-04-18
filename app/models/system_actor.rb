class SystemActor
  def self.identity
    Identity.find_by!(email_address: email)
  end

  def self.user
    @user ||= identity.users.find_by!(role: :system)
  end

  def self.email
    "system@#{install_hostname}"
  end

  def self.install_hostname
    Rails.application.config.x.fizzy.install_hostname or
      raise "Rails.application.config.x.fizzy.install_hostname is not set"
  end
end

