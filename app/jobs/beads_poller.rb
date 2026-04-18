class BeadsPoller < ApplicationJob
  # Per S9 §A.1: single mirror-engine recurring job. 30-second tick by
  # default (see config/recurring.yml when this lands). Runs in:
  #   - Account.singleton context (single-tenant install per P10)
  #   - SystemActor email as Current.actor (system-attributed bd writes
  #     emitted by drift-correction procedures, e.g. fizzy-pmi.9)
  #   - Current.beads_mirror = true → poller-originated writes bypass
  #     Card-side callbacks (S8 §B.4 / fizzy-n3l.5 mirror-mode guard)
  queue_as :default

  def perform
    Current.with(actor: actor_email, beads_mirror: true) do
      Beads::Mirror::Cursor.advance_all
    end
  end

  private
    def actor_email
      SystemActor.email
    rescue => e
      Rails.logger.error "[BeadsPoller] cannot resolve SystemActor.email: #{e.message} — skipping tick"
      raise
    end
end
