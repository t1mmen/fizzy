class Columns::Cards::Drops::NotNowsController < ApplicationController
  include CardScoped

  def create
    Fizzy::Beads::CommandClient.current.defer_issue(@card.id)
  end
end
