# Per S7 §E.2: per-account storage quota config (V1 single-tenant install).
# Override defaults here for production installs.
#
# Defaults (defined as constants in app/models/account/storage.rb):
#   storage_quota_bytes:            50.gigabytes
#   storage_warn_threshold:         0.85  (85% triggers UI warning)
#   storage_hard_reject_threshold:  1.0   (100% blocks new uploads)
#
# To override (uncomment + set):
#
# Rails.application.config.x.fizzy ||= ActiveSupport::OrderedOptions.new
# Rails.application.config.x.fizzy.storage_quota_bytes           = 100.gigabytes
# Rails.application.config.x.fizzy.storage_warn_threshold        = 0.9
# Rails.application.config.x.fizzy.storage_hard_reject_threshold = 1.0

Rails.application.config.x.fizzy ||= ActiveSupport::OrderedOptions.new
