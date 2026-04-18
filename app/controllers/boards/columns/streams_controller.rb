class Boards::Columns::StreamsController < ApplicationController
  include BoardScoped

  def show
    projector = Board::Projector.new(@board, user: Current.user)
    stream_column = Column.new(board: @board, beads_status: "open")
    stream_cards = projector.cards_for_column(stream_column).active

    set_page_and_extract_portion_from stream_cards.latest.with_golden_first.preloaded
    fresh_when etag: @page.records
  end
end
