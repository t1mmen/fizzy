class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :identity, :account, :actor
  attribute :http_method, :request_id, :user_agent, :ip_address, :referrer
  # S8 §B.4 + S9 §A.1: mirror-mode guard — set true by BeadsPoller#perform so
  # poller-originated writes (Card#touch_last_active_at, etc.) bypass callbacks
  # that would otherwise emit Beads-events-twice. Falsy in all other contexts.
  attribute :beads_mirror

  def beads_mirror?
    beads_mirror.present?
  end

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
