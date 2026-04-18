require "test_helper"

class Account::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "show" do
    get account_settings_path
    assert_response :success
  end

  test "update" do
    put account_settings_path, params: { account: { name: "New Account Name" } }
    assert_equal "New Account Name", Current.account.reload.name
    assert_redirected_to account_settings_path
  end

  test "update as JSON" do
    put account_settings_path, params: { account: { name: "New Account Name" } }, as: :json

    assert_response :no_content
    assert_equal "New Account Name", Current.account.reload.name
  end

  test "update requires admin" do
    logout_and_sign_in_as :david

    put account_settings_path, params: { account: { name: "New Account Name" } }
    assert_response :forbidden
  end

  test "show as JSON" do
    get account_settings_path, as: :json

    assert_response :success
    assert_equal Current.account.name, @response.parsed_body["name"]
    assert_equal Current.account.cards_count, @response.parsed_body["cards_count"]
    assert_equal Current.account.entropy.auto_postpone_period_in_days, @response.parsed_body["auto_postpone_period_in_days"]
  end

  # S7 §E.4 (fizzy-8jc): storage settings panel — read-only data path.

  test "show renders storage progress bar with current/total bytes" do
    get account_settings_path

    assert_response :success
    assert_select "[data-test='storage-summary']" do
      assert_select "progress[data-test='storage-progress']" do |elements|
        bar = elements.first
        assert_equal Current.account.bytes_used.to_s, bar["value"]
        assert_equal Current.account.storage_quota_bytes.to_s, bar["max"]
      end
    end
  end

  test "show emits warn-state class when over warn threshold" do
    Account.any_instance.stubs(:bytes_used).returns(Current.account.storage_warn_bytes + 1)

    get account_settings_path

    assert_response :success
    assert_select "[data-test='storage-warn']"
    assert_select ".storage-progress--warn"
  end
end
