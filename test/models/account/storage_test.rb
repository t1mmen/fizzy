require "test_helper"

class Account::StorageTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:"37s")
  end

  test "storage_quota_bytes returns the default 50 GiB when no override" do
    Rails.application.config.x.fizzy.storage_quota_bytes = nil
    assert_equal 50.gigabytes, @account.storage_quota_bytes
  end

  test "storage_quota_bytes picks up initializer override" do
    original = Rails.application.config.x.fizzy.storage_quota_bytes
    Rails.application.config.x.fizzy.storage_quota_bytes = 100.gigabytes
    assert_equal 100.gigabytes, @account.storage_quota_bytes
  ensure
    Rails.application.config.x.fizzy.storage_quota_bytes = original
  end

  test "storage_warn_threshold defaults to 0.85" do
    Rails.application.config.x.fizzy.storage_warn_threshold = nil
    assert_in_delta 0.85, @account.storage_warn_threshold, 0.001
  end

  test "storage_hard_reject_threshold defaults to 1.0" do
    Rails.application.config.x.fizzy.storage_hard_reject_threshold = nil
    assert_in_delta 1.0, @account.storage_hard_reject_threshold, 0.001
  end

  test "storage_warn_bytes computes from quota + threshold" do
    Rails.application.config.x.fizzy.storage_quota_bytes = 100.gigabytes
    Rails.application.config.x.fizzy.storage_warn_threshold = 0.9
    assert_equal (100.gigabytes * 0.9).to_i, @account.storage_warn_bytes
  ensure
    Rails.application.config.x.fizzy.storage_quota_bytes = nil
    Rails.application.config.x.fizzy.storage_warn_threshold = nil
  end

  test "storage_quota_exceeded? false when under quota" do
    Rails.application.config.x.fizzy.storage_quota_bytes = 100.gigabytes
    @account.stubs(:bytes_used).returns(1.gigabyte)
    assert_not @account.storage_quota_exceeded?
    assert_not @account.storage_quota_exceeded?(1.gigabyte)
  ensure
    Rails.application.config.x.fizzy.storage_quota_bytes = nil
  end

  test "storage_quota_exceeded? true when prospective addition crosses hard threshold" do
    Rails.application.config.x.fizzy.storage_quota_bytes = 100.megabytes
    @account.stubs(:bytes_used).returns(95.megabytes)
    assert @account.storage_quota_exceeded?(10.megabytes)
  ensure
    Rails.application.config.x.fizzy.storage_quota_bytes = nil
  end

  test "storage_quota_warning? true at or above warn threshold" do
    Rails.application.config.x.fizzy.storage_quota_bytes = 100.megabytes
    Rails.application.config.x.fizzy.storage_warn_threshold = 0.85
    @account.stubs(:bytes_used).returns(90.megabytes)
    assert @account.storage_quota_warning?
  ensure
    Rails.application.config.x.fizzy.storage_quota_bytes = nil
    Rails.application.config.x.fizzy.storage_warn_threshold = nil
  end

  test "storage_quota_warning? false when below warn threshold" do
    Rails.application.config.x.fizzy.storage_quota_bytes = 100.megabytes
    Rails.application.config.x.fizzy.storage_warn_threshold = 0.85
    @account.stubs(:bytes_used).returns(50.megabytes)
    assert_not @account.storage_quota_warning?
  ensure
    Rails.application.config.x.fizzy.storage_quota_bytes = nil
    Rails.application.config.x.fizzy.storage_warn_threshold = nil
  end
end
