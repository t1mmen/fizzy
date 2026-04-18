class Public::BoardsController < Public::BaseController
  def show
    @projector = Board::Projector.new(@board, user: Current.user)
    stream_column = Column.new(board: @board, beads_status: "open")
    stream_cards = @projector.cards_for_column(stream_column).active
    @stream_cards_count = stream_cards.count

    set_page_and_extract_portion_from stream_cards.latest.with_golden_first
  end
end
