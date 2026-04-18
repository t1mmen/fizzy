require "test_helper"

class BeadsActorTenantedTest < ActiveSupport::TestCase
  class TestJob < ApplicationJob
    def perform
      $performed_actor = Current.actor
    end
  end

  setup do
    $performed_actor = nil
  end

  test "serializes and restores beads_actor across job boundary" do
    job = nil

    Current.with(actor: "x@y.com") do
      job = TestJob.perform_later
    end

    assert_equal "x@y.com", job.serialize["beads_actor"]

    perform_enqueued_jobs

    assert_equal "x@y.com", $performed_actor
  end

  test "does not leak actor when job enqueued without actor" do
    Current.with(actor: "x@y.com") { TestJob.perform_later }
    perform_enqueued_jobs
    assert_equal "x@y.com", $performed_actor

    $performed_actor = nil

    TestJob.perform_later
    perform_enqueued_jobs
    assert_nil $performed_actor
  end
end

