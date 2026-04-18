class Cards::ClosuresController < ApplicationController
  include CardScoped

  def create
    capture_card_location
    client = Fizzy::Beads::CommandClient.current
    client.update_prior_status(@card.id, @card.beads_status.presence || "open")
    client.close_issue(@card.id)
    @card.update_columns(beads_status: "closed", closed_at: Time.current, updated_at: Time.current)
    refresh_stream_if_needed

    respond_to do |format|
      format.turbo_stream
      format.json { head :no_content }
    end
  end

  def destroy
    client = Fizzy::Beads::CommandClient.current
    restore_status = read_prior_status(client, @card.id)
    client.reopen_issue(@card.id, restore_status: restore_status)
    @card.update_columns(beads_status: restore_status, closed_at: nil, close_reason: nil, updated_at: Time.current)
    @card.closure&.destroy
    refresh_stream_after_reopen

    respond_to do |format|
      format.turbo_stream
      format.json { head :no_content }
    end
  end

  private
    def read_prior_status(client, card_id)
      issue = client.read_issue(card_id)
      issue.dig("metadata", "fizzy", "prior_status").presence || "open"
    rescue JSON::ParserError, TypeError
      "open"
    end

    def refresh_stream_after_reopen
      if @card.awaiting_triage?
        set_page_and_extract_portion_from @board.cards.awaiting_triage.latest.with_golden_first.preloaded
      end
    end
end
