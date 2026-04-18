require "test_helper"

class Fizzy::Beads::CommandClientTest < ActiveSupport::TestCase
  def ok_status
    Struct.new(:success?, :exitstatus).new(true, 0)
  end

  test ".for(Identity) extracts email_address" do
    identity = identities(:david)
    client = Fizzy::Beads::CommandClient.for(identity, bd_bin: "bd")

    Open3.expects(:capture3)
      .with("bd", "--actor", identity.email_address, "update", "fizzy-abc", "--status", "blocked")
      .returns(["", "", ok_status])

    client.update_status("fizzy-abc", "blocked")
  end

  test ".for(String) passes through actor email string" do
    client = Fizzy::Beads::CommandClient.for("actor@example.com", bd_bin: "bd")

    Open3.expects(:capture3)
      .with("bd", "--actor", "actor@example.com", "update", "fizzy-abc", "--status", "blocked")
      .returns(["", "", ok_status])

    client.update_status("fizzy-abc", "blocked")
  end

  test ".for(nil) raises MissingActorError" do
    assert_raises(Fizzy::Beads::CommandClient::MissingActorError) do
      Fizzy::Beads::CommandClient.for(nil)
    end
  end

  test ".for(blank String) raises MissingActorError" do
    assert_raises(Fizzy::Beads::CommandClient::MissingActorError) do
      Fizzy::Beads::CommandClient.for("")
    end
  end

  test ".for(unsupported type) raises ArgumentError" do
    assert_raises(ArgumentError) do
      Fizzy::Beads::CommandClient.for(123)
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

  test ".current uses Current.actor" do
    previous = Current.actor
    Current.actor = "current@example.com"

    client = Fizzy::Beads::CommandClient.current(bd_bin: "bd")
    Open3.expects(:capture3)
      .with("bd", "--actor", "current@example.com", "update", "fizzy-abc", "--status", "open")
      .returns(["", "", ok_status])

    client.update_status("fizzy-abc", "open")
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

    status = ok_status

    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "show", "fizzy-abc").returns(["ok", "", status])

    assert_equal "ok", client.send(:invoke!, ["show", "fizzy-abc"])
  end

  test "invoke! wraps Errno::ENOENT as CommandError with status=nil" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")
    Open3.stubs(:capture3).raises(Errno::ENOENT.new("no such file or directory - bd"))

    error = assert_raises(Fizzy::Beads::CommandClient::CommandError) do
      client.send(:invoke!, ["show", "fizzy-abc"])
    end

    assert_nil error.status
    assert_match(/no such file or directory/i, error.stderr)
  end

  test "update_status calls bd update --status" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")

    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--status", "blocked").returns(["", "", ok_status])

    client.update_status("fizzy-abc", "blocked")
  end

  test "close_issue calls bd close and supports --reason" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")

    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "close", "fizzy-abc", "--reason", "done").returns(["", "", ok_status])

    client.close_issue("fizzy-abc", reason: "done")
  end

  test "reopen_issue optionally restores status via a second update" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")

    sequence = sequence("bd")
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "reopen", "fizzy-abc").in_sequence(sequence).returns(["", "", ok_status])
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--status", "in_progress").in_sequence(sequence).returns(["", "", ok_status])

    client.reopen_issue("fizzy-abc", restore_status: "in_progress")
  end

  test "defer_issue supports until_time and until keyword" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")

    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "defer", "fizzy-abc", "--until=tomorrow").returns(["", "", ok_status])
    client.defer_issue("fizzy-abc", until_time: "tomorrow")

    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "defer", "fizzy-abc", "--until=next monday").returns(["", "", ok_status])
    client.defer_issue("fizzy-abc", until: "next monday")
  end

  test "read_issue uses --json show and parses JSON" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")

    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "--json", "show", "fizzy-abc").returns([ "{\"id\":\"fizzy-abc\"}", "", ok_status ])

    assert_equal({ "id" => "fizzy-abc" }, client.read_issue("fizzy-abc"))
  end

  test "undefer_issue optionally restores status via a second update" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")

    sequence = sequence("bd")
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "undefer", "fizzy-abc").in_sequence(sequence).returns(["", "", ok_status])
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--status", "open").in_sequence(sequence).returns(["", "", ok_status])

    client.undefer_issue("fizzy-abc", restore_status: "open")
  end

  test "update_defer_until uses bd update --defer with RFC3339 string" do
    client = Fizzy::Beads::CommandClient.for("x@y.com", bd_bin: "bd")

    timestamp = "2026-04-18T03:43:56Z"
    Open3.expects(:capture3).with("bd", "--actor", "x@y.com", "update", "fizzy-abc", "--defer", timestamp).returns(["", "", ok_status])

    client.update_defer_until("fizzy-abc", until_time: timestamp)
  end
end
