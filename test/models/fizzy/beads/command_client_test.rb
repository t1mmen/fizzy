require "test_helper"

class Fizzy::Beads::CommandClientTest < ActiveSupport::TestCase
  test ".for(nil) raises MissingActorError" do
    assert_raises(Fizzy::Beads::CommandClient::MissingActorError) do
      Fizzy::Beads::CommandClient.for(nil)
    end
  end

  test ".current raises MissingActorError when Current.actor is unset" do
    previous = Current.actor
    Current.actor = nil

    assert_raises(Fizzy::Beads::CommandClient::MissingActorError) do
      Fizzy::Beads::CommandClient.current
    end
  ensure
    Current.actor = previous
  end

  test "invoke! prefixes argv with --actor and raises on non-zero exit" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")

    status = Struct.new(:success?, :exitstatus).new(false, 2)

    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "create", "issue").returns(["", "nope", status])

    error = assert_raises(Fizzy::Beads::CommandClient::CommandError) do
      client.send(:invoke!, ["create", "issue"])
    end

    assert_equal ["bd", "--actor", "x@y.com", "create", "issue"], error.argv
    assert_equal status, error.status
    assert_equal "nope", error.stderr
  end

  test "invoke! returns stdout on success" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")

    status = Struct.new(:success?, :exitstatus).new(true, 0)

    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "show", "fizzy-abc").returns(["ok", "", status])

    assert_equal "ok", client.send(:invoke!, ["show", "fizzy-abc"])
  end
end
