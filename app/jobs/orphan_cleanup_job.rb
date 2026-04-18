class OrphanCleanupJob < ApplicationJob
  # Per S7 §F.1 + S9 §D.3: when a Beads issue is hard-deleted via CLI
  # (rare in V1 — no UI button), the S9 poller detects the missing issue
  # on next tick and enqueues this job for cleanup.
  #
  # Wraps Card#destroy in Storage::Entry.suppressing_recording so the AR
  # dependent: :destroy cascade (action_text_rich_texts → attachments)
  # does NOT emit re-balancing negative deltas in the storage ledger
  # (the account/board totals are already correct since the storage
  # entries don't need accounting "delete" rows for orphan cleanup).
  #
  # Blob retention period (default 24h) governs the actual S3/disk file
  # purge — this job is a best-effort logical cleanup.
  queue_as :default

  def perform(issue_id)
    card = Card.find_by(id: issue_id.to_s)
    return unless card

    Storage::Entry.suppressing_recording do
      card.destroy
    end
  end
end
