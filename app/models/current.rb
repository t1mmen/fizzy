class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :identity, :account, :actor
  attribute :http_method, :request_id, :user_agent, :ip_address, :referrer

  def session=(value)
    super(value)

    if value.present?
      self.identity = session.identity
    end
  end

  def identity=(identity)
    super(identity)

    if identity.present?
      self.actor = identity.email_address
      self.user = identity.users.find_by(account: account)
    else
      self.actor = nil
    end
  end

  def with_account(value, &)
    with(account: value, &)
  end

  def without_account(&)
    with(account: nil, &)
  end
end
