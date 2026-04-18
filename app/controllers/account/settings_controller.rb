class Account::SettingsController < ApplicationController
  wrap_parameters :account, include: %i[ name ]

  before_action :ensure_admin, only: :update
  before_action :set_account

  def show
    respond_to do |format|
      format.html do
        @users = @account.users.active.alphabetically.includes(:identity)
        load_storage_summary
      end
      format.json
    end
  end

  def update
    @account.update!(account_params)

    respond_to do |format|
      format.html { redirect_to account_settings_path }
      format.json { head :no_content }
    end
  end

  private
    def set_account
      @account = Current.account
    end

    def account_params
      params.expect account: %i[ name ]
    end

    # S7 §E.4 (fizzy-8jc): read-only storage summary for the settings page —
    # current bytes, quota cap, warn threshold, plus per-board breakdown so
    # admins can see "what's using my storage".
    def load_storage_summary
      @storage_usage_bytes      = @account.bytes_used
      @storage_quota_bytes      = @account.storage_quota_bytes
      @storage_warn_bytes       = @account.storage_warn_bytes
      @storage_quota_warning    = @account.storage_quota_warning?
      @storage_per_board        = @account.boards.includes(:storage_total).map { |b| [ b, b.bytes_used ] }
                                                  .sort_by { |_, bytes| -bytes }
    end
end
