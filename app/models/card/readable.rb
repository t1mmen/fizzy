module Card::Readable
  extend ActiveSupport::Concern

  def read_by(user)
    user.notifications.find_by(card: self)&.tap(&:read)
  end

  def unread_by(user)
    user.notifications.find_by(card: self)&.tap(&:unread)
  end

  def remove_inaccessible_notifications
    accessible_user_ids = board.accesses.pluck(:user_id)
    # Notifications are always card-scoped via notifications.card_id, so
    # don't attempt to match by polymorphic source relations (Event/Mention
    # ids may be stored in non-comparable formats across adapters).
    Notification.where(card: self).where.not(user_id: accessible_user_ids).in_batches.destroy_all
  end

  private
    def remove_inaccessible_notifications_later
      Card::RemoveInaccessibleNotificationsJob.perform_later(self)
    end

    def event_notification_sources
      events.or(comment_creation_events)
    end

    def comment_creation_events
      Event.where(eventable: comments)
    end

    def inaccessible_notifications_from(sources, accessible_user_ids)
      Notification.where(source: sources).where.not(user_id: accessible_user_ids)
    end

    def notification_sources
      [ events, comment_creation_events, mentions, comment_mentions ]
    end

    def mention_notification_sources
      mentions.or(comment_mentions)
    end

    def comment_mentions
      Mention.where(source: comments)
    end
end
