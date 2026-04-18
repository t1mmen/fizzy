module Card::Entropic
  extend ActiveSupport::Concern

  included do
    scope :due_to_be_postponed, -> do
      active
        .joins(board: :account)
        .left_outer_joins(board: :entropy)
        .joins("LEFT OUTER JOIN entropies AS account_entropies ON account_entropies.account_id = accounts.id AND account_entropies.container_type = 'Account' AND account_entropies.container_id = accounts.id")
        .where("last_active_at <= #{connection.date_subtract('?', 'COALESCE(entropies.auto_postpone_period, account_entropies.auto_postpone_period)')}", Time.now)
    end

    scope :postponing_soon, -> do
      now = Time.now
      active
        .joins(board: :account)
        .left_outer_joins(board: :entropy)
        .joins("LEFT OUTER JOIN entropies AS account_entropies ON account_entropies.account_id = accounts.id AND account_entropies.container_type = 'Account' AND account_entropies.container_id = accounts.id")
        .where("last_active_at > #{connection.date_subtract('?', 'COALESCE(entropies.auto_postpone_period, account_entropies.auto_postpone_period)')}", now)
        .where("last_active_at <= #{connection.date_subtract('?', 'COALESCE(entropies.auto_postpone_period, account_entropies.auto_postpone_period) * 0.75')}", now)
    end

    delegate :auto_postpone_period, to: :board
  end

  class_methods do
    def auto_postpone_all_due
      Current.with(actor: SystemActor.email) do
        due_to_be_postponed.find_each do |card|
          until_time = Time.current + card.auto_postpone_period.to_i
          Fizzy::Beads::CommandClient.current.defer_issue(card.id, until: until_time.iso8601)

          # Mirror the defer_until locally so UI can reflect "Not now" before
          # the poller sweep lands (S4 §C.3 mirror columns).
          card.update_columns(defer_until: until_time, updated_at: Time.current)
          card.activity_spike&.destroy
        end
      end
    end
  end

  def entropy
    Card::Entropy.for(self)
  end

  def entropic?
    entropy.present?
  end
end
