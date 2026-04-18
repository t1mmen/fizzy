require "test_helper"

# S3 F.9 (fizzy-efe): ensure actor context survives the request→job boundary.
class BeadsActorTenantedTest < ActiveJob::TestCase
  class CaptureActorJob < ApplicationJob
    cattr_accessor :captured_actor, default: nil

    def perform
      self.class.captured_actor = Current.actor
    end
  end

  class CommandClientCurrentJob < ApplicationJob
    def perform(card_id)
      Fizzy::Beads::CommandClient.current.update_status(card_id, "open")
    end
  end

  class CommandClientCurrentWithoutActorJob < ApplicationJob
    cattr_accessor :captured_error_class, default: nil

    def perform(card_id)
      Fizzy::Beads::CommandClient.current.update_status(card_id, "open")
    rescue => e
      self.class.captured_error_class = e.class
    end
  end

  def ok_status
    Struct.new(:success?, :exitstatus).new(true, 0)
  end

  setup do
    CaptureActorJob.captured_actor = nil
    CommandClientCurrentWithoutActorJob.captured_error_class = nil
  end

  test "serialize includes beads_actor captured at enqueue time" do
    job = nil

    Current.with(actor: "x@y.com") do
      job = CaptureActorJob.new
    end

    assert_equal "x@y.com", job.serialize["beads_actor"]
  end

  test "deserialize+perform restores Current.actor during execution" do
    outside = "outside@example.com"
    Current.actor = outside

    Current.with(actor: "x@y.com") do
      CaptureActorJob.perform_later
    end

    perform_enqueued_jobs

    assert_equal "x@y.com", CaptureActorJob.captured_actor
    assert_equal outside, Current.actor
  ensure
    Current.actor = nil
  end

  test "CommandClient.current inside a job uses the captured actor (--actor argv)" do
    card_id = "fizzy-job-001"
    status = ok_status

    Open3.expects(:capture3)
      .with("bd", "--actor", "x@y.com", "update", card_id, "--status", "open")
      .returns(["", "", status])

    Current.with(actor: "x@y.com") do
      CommandClientCurrentJob.perform_later(card_id)
    end

    perform_enqueued_jobs
  end

  test "job enqueued without Current.actor does not restore; CommandClient.current raises MissingActorError" do
    card_id = "fizzy-job-002"

    CommandClientCurrentWithoutActorJob.perform_later(card_id)
    perform_enqueued_jobs

    assert_equal Fizzy::Beads::CommandClient::MissingActorError, CommandClientCurrentWithoutActorJob.captured_error_class
  end
end

