module Account::Storage
  extend ActiveSupport::Concern
  include Storage::Totaled

  # S7 §E.2: per-account storage quota config (V1 single-tenant means
  # install-level). Defaults applied here are overridable via initializer
  # at config/initializers/storage_quota.rb assigning to
  # Rails.application.config.x.fizzy.storage_*.
  DEFAULT_STORAGE_QUOTA_BYTES = 50.gigabytes
  DEFAULT_STORAGE_WARN_THRESHOLD = 0.85
  DEFAULT_STORAGE_HARD_REJECT_THRESHOLD = 1.0

  included do
    before_destroy :clear_storage_entries
  end

  def storage_quota_bytes
    config_value(:storage_quota_bytes, DEFAULT_STORAGE_QUOTA_BYTES).to_i
  end

  def storage_warn_threshold
    config_value(:storage_warn_threshold, DEFAULT_STORAGE_WARN_THRESHOLD).to_f
  end

  def storage_hard_reject_threshold
    config_value(:storage_hard_reject_threshold, DEFAULT_STORAGE_HARD_REJECT_THRESHOLD).to_f
  end

  def storage_warn_bytes
    (storage_quota_bytes * storage_warn_threshold).to_i
  end

  def storage_quota_exceeded?(prospective_added_bytes = 0)
    (bytes_used + prospective_added_bytes) >= (storage_quota_bytes * storage_hard_reject_threshold)
  end

  def storage_quota_warning?
    bytes_used >= storage_warn_bytes
  end

  private
    def clear_storage_entries
      Storage::Entry.where(account_id: id).delete_all
    end

    def calculate_real_storage_bytes
      boards.sum { |board| board.send(:calculate_real_storage_bytes) }
    end

    def config_value(key, default)
      Rails.application.config.x.fizzy&.public_send(key) || default
    rescue NoMethodError
      default
    end
end
