require "test_helper"

# S9 F.2: BeadsPoller is the single mirror-engine recurring job. Sets up
# Current.actor + Current.beads_mirror per S9 §A.1, calls advance_all.
class BeadsPollerTest < ActiveJob::TestCase
  setup do
    @previous_install_hostname = Rails.application.config.x.fizzy.install_hostname
    Rails.application.config.x.fizzy.install_hostname = "test.fizzy.localhost"
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = @previous_install_hostname
  end

  test "perform sets Current.actor to SystemActor.email and Current.beads_mirror" do
    captured = {}
    Beads::Mirror::Cursor.stubs(:advance_all).with do
      captured[:actor] = Current.actor
      captured[:mirror] = Current.beads_mirror
      true
    end

    BeadsPoller.perform_now

    assert_equal SystemActor.email, captured[:actor]
    assert_equal true, captured[:mirror]
  end

  test "perform restores Current state after the block" do
    Current.actor = "outside@example.com"
    Current.beads_mirror = nil
    Beads::Mirror::Cursor.stubs(:advance_all)

    BeadsPoller.perform_now

    assert_equal "outside@example.com", Current.actor
    assert_nil Current.beads_mirror
  end

  test "perform raises if SystemActor.email cannot be resolved" do
    previous = Rails.application.config.x.fizzy.install_hostname
    Rails.application.config.x.fizzy.install_hostname = nil

    assert_raises(RuntimeError) do
      BeadsPoller.perform_now
    end
  ensure
    Rails.application.config.x.fizzy.install_hostname = previous
  end

  test "advance_all iterates all SOURCES and updates last_advanced_at via stub" do
    Beads::Mirror::Cursor.advance_all

    Beads::Mirror::Cursor::SOURCES.each do |source|
      cursor = Beads::Mirror::Cursor.find_by(source: source)
      assert_not_nil cursor, "expected cursor row for source=#{source}"
      assert_not_nil cursor.last_advanced_at, "expected last_advanced_at to be set"
    end
  end

  test "advance_all swallows errors from individual source procedures (does not crash other sources)" do
    Beads::Mirror::Cursor::PROCEDURES[Beads::Mirror::Cursor::EVENTS] = ->(_) { raise "boom" }

    assert_nothing_raised do
      Beads::Mirror::Cursor.advance_all
    end

    # Other sources still ran via the stub
    assert_not_nil Beads::Mirror::Cursor.find_by(source: Beads::Mirror::Cursor::COMMENTS)
  ensure
    Beads::Mirror::Cursor::PROCEDURES.delete(Beads::Mirror::Cursor::EVENTS)
  end
end
