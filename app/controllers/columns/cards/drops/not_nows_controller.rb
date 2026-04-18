class Columns::Cards::Drops::NotNowsController < ApplicationController
  include CardScoped

  def create
    client = Fizzy::Beads::CommandClient.current
    client.update_prior_status(@card.id, @card.beads_status.presence || "open")
    client.defer_issue(@card.id)
    @card.update_columns(defer_until: Time.current, updated_at: Time.current)
  end
end
