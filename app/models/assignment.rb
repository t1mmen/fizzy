class Assignment < ApplicationRecord
  LIMIT = 100

  belongs_to :account, default: -> { card.account }
  belongs_to :card, touch: true

  belongs_to :assignee, class_name: "User"
  belongs_to :assigner, class_name: "User"

  validate :within_limit, on: :create

  # S5 §F.3 (fizzy-7dc): Fizzy assignments table is canonical for multi-
  # assignee. Beads issues.assignee is single-value, so we mirror the
  # PRIMARY assignee (chronologically first by created_at) to Beads via
  # CommandClient on every sidecar mutation.
  after_create_commit :sync_primary_assignee_to_beads
  after_destroy_commit :sync_primary_assignee_to_beads

  private
    def within_limit
      if card.assignments.count >= LIMIT
        errors.add(:base, "Card already has the maximum of #{LIMIT} assignees")
      end
    end

    # Mirror the chronologically-first assignee's email to Beads. Per S5
    # §F.4: when all assignees removed, pass empty string to clear Beads
    # assignee. When primary changes, the next-oldest becomes primary.
    #
    # Skipped when:
    #   - card.id is not a Beads issue id (legacy uuid-style cards have
    #     no Beads issue to mirror to)
    #   - in mirror-mode (S8 §B.4) — poller-originated writes shouldn't
    #     re-emit
    #   - Current.actor is not set (no actor → CommandClient raises;
    #     gracefully skip with a log line)
    def sync_primary_assignee_to_beads
      return unless card.id.to_s.start_with?("fizzy-")
      return if Current.beads_mirror?
      return unless Current.actor.present?

      primary = card.reload.assignments.order(:created_at).first
      primary_email = primary&.assignee&.identity&.email_address || ""
      Fizzy::Beads::CommandClient.current.set_assignee(card.id, primary_email)
    rescue => e
      Rails.logger.warn "[Assignment#sync_primary_assignee_to_beads] card=#{card.id} skipped: #{e.class}: #{e.message}"
    end
end
