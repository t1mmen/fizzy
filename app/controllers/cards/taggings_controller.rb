class Cards::TaggingsController < ApplicationController
  include CardScoped

  def new
    # S2 F.9 (fizzy-eq4.9): system labels under the reserved `fizzy/` namespace
    # (board membership, etc.) are not user-selectable. They remain mirrored into
    # MySQL for projection, but are hidden from the tag picker UI.
    system_prefix = "fizzy/%"
    @tagged_with = @card.tags.alphabetically.where.not("tags.title LIKE ?", system_prefix)
    @tags = Current.account.tags.all.alphabetically.where.not("tags.title LIKE ?", system_prefix).where.not(id: @tagged_with)
    fresh_when etag: [ @tags, @card.tags ]
  end

  # S5 §G (fizzy-69z): for Beads-id cards we delegate to CommandClient and let
  # the S9 poller mirror the change back. For legacy uuid-id cards (no Beads
  # issue) we fall back to direct AR mutation via Card#toggle_tag_with.
  def create
    title = normalize_or_reject(params.required(:tag_title)) or return

    if mirrored?
      Fizzy::Beads::CommandClient.current.add_label(@card.id, title)
    else
      @card.toggle_tag_with(title)
    end

    respond_to do |format|
      format.turbo_stream
      format.json { head :no_content }
    end
  end

  def destroy
    title = normalize_or_reject(params[:id]) or return

    if mirrored?
      Fizzy::Beads::CommandClient.current.remove_label(@card.id, title)
    elsif tag = @card.tags.find_by(title: title)
      @card.taggings.destroy_by(tag: tag)
    end

    respond_to do |format|
      format.turbo_stream { render :create }
      format.json { head :no_content }
    end
  end

  private
    def mirrored?
      @card.id.to_s.start_with?("fizzy-")
    end

    def normalize_or_reject(raw)
      title = Fizzy::Beads::LabelNormalizer.call(raw)
      if Fizzy::Beads::ReservedNamespace.violates?(title)
        head :unprocessable_entity
        nil
      else
        title
      end
    rescue Fizzy::Beads::LabelNormalizer::InvalidLabelError
      head :unprocessable_entity
      nil
    end
end
