class Cards::ClosuresController < ApplicationController
  include CardScoped

  def create
    capture_card_location
    Fizzy::Beads::CommandClient.current.close_issue(@card.id)
    @card.update_columns(beads_status: "closed", closed_at: Time.current, updated_at: Time.current)
    refresh_stream_if_needed

    respond_to do |format|
      format.turbo_stream
      format.json { head :no_content }
    end
  end

  def destroy
    Fizzy::Beads::CommandClient.current.reopen_issue(@card.id)
    @card.update_columns(beads_status: "open", closed_at: nil, close_reason: nil, updated_at: Time.current)
    @card.closure&.destroy
    refresh_stream_after_reopen

    respond_to do |format|
      format.turbo_stream
      format.json { head :no_content }
    end
  end

  private
    def refresh_stream_after_reopen
      if @card.awaiting_triage?
        set_page_and_extract_portion_from @board.cards.awaiting_triage.latest.with_golden_first.preloaded
      end
    end
end
