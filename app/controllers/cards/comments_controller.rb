class Cards::CommentsController < ApplicationController
  wrap_parameters :comment, include: %i[ body created_at ]
  include CardScoped

  before_action :set_comment, only: %i[ show edit update destroy ]
  before_action :ensure_creatorship, only: %i[ edit update destroy ]
  before_action :ensure_card_is_commentable, only: :create

  def index
    set_page_and_extract_portion_from @card.comments.chronologically
  end

  def create
    plaintext = Fizzy::Beads::ActionTextToPlaintext.call(comment_params[:body])
    json = Fizzy::Beads::CommandClient.current.add_comment(@card.id, plaintext)
    
    # Per S6 §E.2: Optimistic mirror write for immediate response
    @comment = Beads::Mirror::CommentMirror.call(json, account_id: @card.account_id)

    respond_to do |format|
      format.turbo_stream
      format.json { render :show, status: :created, location: card_comment_path(@card, @comment, format: :json) }
    end
  end

  def show
  end

  def edit
    head :method_not_allowed
  end

  def update
    head :method_not_allowed
  end

  def destroy
    head :method_not_allowed
  end

  private
    def set_comment
      @comment = @card.comments.find(params[:id])
    end

    def ensure_creatorship
      head :forbidden if Current.user != @comment.creator
    end

    def ensure_card_is_commentable
      head :forbidden unless @card.commentable?
    end

    def comment_params
      params.expect(comment: [ :body, :created_at ])
    end
end
