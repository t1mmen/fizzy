# Per S3 §F.2: stable install hostname for system actor email.
#
# Override with:
#   FIZZY_INSTALL_HOSTNAME=fizzy.example.com
Rails.application.config.x.fizzy ||= ActiveSupport::OrderedOptions.new

Rails.application.config.x.fizzy.install_hostname ||=
  ENV["FIZZY_INSTALL_HOSTNAME"].presence ||
  begin
    configured_host = Rails.application.config.action_mailer.default_url_options&.[](:host)
    configured_host.to_s.split(":").first.presence
  end

