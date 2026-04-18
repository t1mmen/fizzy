class TagDeletionJob < ApplicationJob
  # S5 §J.5 (fizzy-ehj): admin-initiated tag deletion. Iterates every Beads-id
  # card carrying the label, removes the label via CommandClient, then deletes
  # the Tag row. Legacy uuid-id cards skip the CommandClient hop (no Beads
  # issue exists). The S9 poller will eventually reconcile any drift.
  def perform(tag)
    tag.cards.find_each do |card|
      remove_label(card, tag.title)
    end

    tag.destroy
  end

  private
    def remove_label(card, title)
      return unless card.id.to_s.start_with?("fizzy-")

      Fizzy::Beads::CommandClient.current.remove_label(card.id, title)
    rescue => e
      Rails.logger.warn "[TagDeletionJob] card=#{card.id} label=#{title} skipped: #{e.class}: #{e.message}"
    end
end
