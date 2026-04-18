class Columns::Cards::Drops::ClosuresController < ApplicationController
  include CardScoped

  def create
    Fizzy::Beads::CommandClient.current.close_issue(@card.id)
    @card.update_columns(beads_status: "closed", closed_at: Time.current, updated_at: Time.current)
  end
end
