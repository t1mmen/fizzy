class BeadsResync < ApplicationJob
  # Per S9 §D.1 (fizzy-pmi.8): periodic full-sweep resync that catches any
  # rows the event-cursor poller missed. Runs nightly (24h cadence — see
  # config/recurring.yml when wired). Calls the per-source mirror
  # procedures (pmi.3 issue, pmi.5 labels, pmi.4 custom statuses) which
  # are all idempotent.
  #
  # Runs in mirror-mode (Current.beads_mirror = true) so any callbacks
  # that DO fall through bypass cascading work (S8 §B.4 / fizzy-n3l.5).
  #
  # The actual Beads SQL iteration (open issues / labels / custom_statuses)
  # is dependency-injected via the `source:` arg so this job is testable
  # without a live Beads connection. Production source is plumbed when
  # the :beads database connection lands as a separate plumbing item.
  queue_as :default

  # Default source: stub returning empty arrays — the BeadsPoller wiring
  # will inject the real Beads SQL source. Tests inject mocks.
  class NullSource
    def open_issues = []
    def labels_for(_issue_id) = []
    def custom_statuses = []
  end

  def perform(source: NullSource.new, account_id: nil, board_id: nil)
    Current.with(actor: actor_email, beads_mirror: true) do
      sweep_issues(source, account_id: account_id, board_id: board_id)
      sweep_custom_statuses(source)
    end
  end

  private
    def sweep_issues(source, account_id:, board_id:)
      # V1 single-tenant per P10 — defaults to the singleton account/board
      # if caller doesn't supply (production wiring will pass explicitly).
      account_id ||= Account.first&.id
      board_id   ||= Board.first&.id
      return unless account_id && board_id

      source.open_issues.each do |issue|
        issue_id = issue.respond_to?(:id) ? issue.id : issue[:id] || issue["id"]
        next if issue_id.blank?

        Beads::Mirror::IssueMirror.call(
          issue,
          account_id: account_id,
          board_id: board_id,
          creator_id: resolve_system_creator_id
        )

        sweep_labels_for(issue_id, source: source, account_id: account_id)
      rescue => e
        Rails.logger.error "[BeadsResync] issue=#{issue_id || '?'} failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    def sweep_labels_for(issue_id, source:, account_id:)
      beads_labels = Array(source.labels_for(issue_id))
      mirror_labels = Tagging.joins(:tag).where(card_id: issue_id.to_s, tags: { account_id: account_id }).pluck("tags.title")

      to_add = beads_labels - mirror_labels
      to_remove = mirror_labels - beads_labels

      to_add.each do |label|
        Beads::Mirror::LabelDelta.apply(operation: :added, account_id: account_id, card_id: issue_id, label: label)
      end
      to_remove.each do |label|
        Beads::Mirror::LabelDelta.apply(operation: :removed, account_id: account_id, card_id: issue_id, label: label)
      end
    end

    def sweep_custom_statuses(source)
      Beads::CustomStatus.refresh_from(source.custom_statuses)
    end

    def actor_email
      SystemActor.email
    rescue
      "system@unknown"  # never crash the resync over actor resolution
    end

    # Falls back to first User row when SystemActor isn't bootstrapped
    # (dev / test envs without fizzy-7j3 system Identity migration applied).
    # In production this returns the system user.
    def resolve_system_creator_id
      SystemActor.user.id
    rescue ActiveRecord::RecordNotFound
      User.first&.id
    end
end
