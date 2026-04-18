class Columns::Cards::Drops::StreamsController < ApplicationController
  include CardScoped

  def create
    @card.send_back_to_triage
    projector = Board::Projector.new(@board, user: Current.user)
    stream_column = Column.new(board: @board, beads_status: "open")
    stream_cards = projector.cards_for_column(stream_column).active

    set_page_and_extract_portion_from stream_cards.latest.with_golden_first
  end
end
