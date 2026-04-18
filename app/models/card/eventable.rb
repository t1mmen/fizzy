module Card::Eventable
  extend ActiveSupport::Concern

  include ::Eventable

  included do
    before_create { self.last_active_at ||= created_at || Time.current }

    after_save :track_title_change, if: :saved_change_to_title?
  end

  def event_was_created(event)
    transaction do
      create_system_comment_for(event)
      touch_last_active_at unless was_just_published?
    end
  end

  def touch_last_active_at
    if Current.beads_mirror?
      # S8 §B.4: poller-originated Event creation must NOT cascade Card-side
      # callbacks (Searchable, Notifiable on Card, etc.) — those re-emissions
      # double the events the poller is mirroring. update_columns bypasses
      # AR callbacks + validations + dirty tracking entirely.
      update_columns(last_active_at: Time.current)
    else
      # Non-mirror path (UI/job/test): preserve existing semantics so callers
      # that rely on Card callbacks (Searchable update, etc.) still fire.
      update!(last_active_at: Time.current)
    end
  end

  private
    def should_track_event?
      published?
    end

    def track_title_change
      if title_before_last_save.present?
        track_event "title_changed", particulars: { old_title: title_before_last_save, new_title: title }
      end
    end

    def create_system_comment_for(event)
      SystemCommenter.new(self, event).comment
    end
end
