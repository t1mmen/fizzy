class Cards::NotNowsController < ApplicationController
  include CardScoped

  def create
    capture_card_location
    client = Fizzy::Beads::CommandClient.current
    client.update_prior_status(@card.id, @card.beads_status.presence || "open")
    client.defer_issue(@card.id)
    @card.update_columns(defer_until: Time.current, updated_at: Time.current)
    refresh_stream_if_needed

    respond_to do |format|
      format.turbo_stream
      format.json { head :no_content }
    end
  end

  def destroy
    client = Fizzy::Beads::CommandClient.current
    restore_status = read_prior_status(client, @card.id)
    client.undefer_issue(@card.id, restore_status: restore_status)
    @card.update_columns(defer_until: nil, beads_status: restore_status, updated_at: Time.current)

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
end
