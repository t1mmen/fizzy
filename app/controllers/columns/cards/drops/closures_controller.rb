class Columns::Cards::Drops::ClosuresController < ApplicationController
  include CardScoped

  def create
    client = Fizzy::Beads::CommandClient.current
    client.update_prior_status(@card.id, @card.beads_status.presence || "open")
    client.close_issue(@card.id)
    @card.update_columns(beads_status: "closed", closed_at: Time.current, updated_at: Time.current)
  end
end
