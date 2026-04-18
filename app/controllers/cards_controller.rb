class CardsController < ApplicationController
  wrap_parameters :card, include: %i[ title description image created_at last_active_at ]

  include FilterScoped

  before_action :set_board, only: %i[ create ]
  before_action :set_card, only: %i[ show edit update destroy ]
  before_action :redirect_if_drafted, only: :show
  before_action :ensure_permission_to_administer_card, only: %i[ destroy ]

  def index
    set_page_and_extract_portion_from @filter.cards
  end

  def create
    respond_to do |format|
      format.html do
        card = Current.user.draft_new_card_in(@board)
        redirect_to card_draft_path(card)
      end

      format.json do
        @card = Card.create! card_params.merge(board: @board, creator: Current.user, status: "published")
        ensure_board_membership_tagging!(@card)
        render :show, status: :created, location: card_path(@card, format: :json)
      end
    end
  end

  def show
  end

  def edit
  end

  def update
    if mirrored? && card_params.key?(:description)
      description_input = card_params[:description]
      other_attributes = card_params.except(:description)

      @card.update!(other_attributes) if other_attributes.to_h.any?
      update_description_via_beads(description_input)
    else
      @card.update! card_params
    end

    respond_to do |format|
      format.turbo_stream
      format.json { render :show }
    end
  end

  def destroy
    @card.destroy!

    respond_to do |format|
      format.html { redirect_to @card.board, notice: "Card deleted" }
      format.json { head :no_content }
    end
  end

  private
    def set_board
      @board = Current.user.boards.find params[:board_id]
    end

    def set_card
      @card = Current.user.accessible_cards.find_by!(number: params[:id])
    end

    def redirect_if_drafted
      redirect_to card_draft_path(@card) if @card.drafted?
    end

    def ensure_permission_to_administer_card
      head :forbidden unless Current.user.can_administer_card?(@card)
    end

    def card_params
      params.expect(card: [ :title, :description, :image, :created_at, :last_active_at ])
    end

    def mirrored?
      @card.id.to_s.start_with?("fizzy-")
    end

    def ensure_board_membership_tagging!(card)
      tag = Tag.find_or_create_by!(account_id: card.account_id, title: card.board.membership_label)
      Tagging.find_or_create_by!(account_id: card.account_id, card_id: card.id, tag_id: tag.id)
    end

    def update_description_via_beads(description_input)
      plaintext = Fizzy::Beads::ActionTextToPlaintext.call(description_input)
      Fizzy::Beads::CommandClient.current.update_description(@card.id, plaintext)

      html = Fizzy::Beads::PlaintextToActionTextHtml.call(plaintext)
      upsert_action_text_description(html)

      # Keep the mirror search index consistent immediately (poller will reconcile).
      search_record_class = Search::Record.for(@card.account_id)
      search_record_class.upsert!(
        account_id: @card.account_id,
        searchable_type: "Card",
        searchable_id: @card.id,
        card_id: @card.id,
        board_id: @card.board_id,
        title: @card.title.to_s,
        content: plaintext.to_s,
        created_at: @card.created_at || Time.current
      )

      @card.update_columns(last_active_at: Time.current, updated_at: Time.current)
    end

    def upsert_action_text_description(html)
      existing = ActionText::RichText.find_by(record_type: "Card", record_id: @card.id, name: "description")
      id = existing&.id || ActiveRecord::Type::Uuid.generate
      created_at = existing&.created_at || Time.current
      now = Time.current

      ActionText::RichText.upsert_all(
        [
          {
            id: id,
            account_id: @card.account_id,
            record_type: "Card",
            record_id: @card.id,
            name: "description",
            body: html.to_s,
            created_at: created_at,
            updated_at: now
          }
        ],
        unique_by: [ :record_type, :record_id, :name ]
      )
    end
end
