class Cards::NotNowsController < ApplicationController
  include CardScoped

  def create
    capture_card_location
    Fizzy::Beads::CommandClient.current.defer_issue(@card.id)
    refresh_stream_if_needed

    respond_to do |format|
      format.turbo_stream
      format.json { head :no_content }
    end
  end
end
