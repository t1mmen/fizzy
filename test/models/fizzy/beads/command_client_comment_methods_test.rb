require "test_helper"

# S6 F.2 (add_comment) + S6 F.3 (update_description). Both use --file
# to avoid quoting/escaping pitfalls; --author = @actor for deterministic
# poller mapping (S6 §C.3); add_comment uses --json + parses response.
class Fizzy::Beads::CommandClientCommentMethodsTest < ActiveSupport::TestCase
  setup do
    @client = Fizzy::Beads::CommandClient.for("alice@example.com", bd_bin: "bd")
    @ok_status = Struct.new(:success?, :exitstatus).new(true, 0)
  end

  # ---- add_comment --------------------------------------------------

  test "add_comment uses bd comments add --file --author --json with the actor email" do
    Open3.expects(:capture3).with do |*argv|
      argv[0] == "bd" &&
        argv[1] == "--actor" &&
        argv[2] == "alice@example.com" &&
        argv[3] == "comments" &&
        argv[4] == "add" &&
        argv[5] == "fizzy-abc" &&
        argv[6] == "--file" &&
        File.exist?(argv[7]) &&
        File.read(argv[7]) == "Hello world" &&
        argv[8] == "--author" &&
        argv[9] == "alice@example.com" &&
        argv[10] == "--json"
    end.returns([ '{"id":"comment-123","created_at":"2026-04-17T22:00:00Z"}', "", @ok_status ])

    result = @client.add_comment("fizzy-abc", "Hello world")
    assert_equal "comment-123", result["id"]
    assert_equal "2026-04-17T22:00:00Z", result["created_at"]
  end

  test "add_comment writes plaintext to a tempfile (multi-line safe)" do
    body = "First line\n\nSecond paragraph\nWith newline"
    Open3.expects(:capture3).with do |*argv|
      argv[6] == "--file" && File.read(argv[7]) == body
    end.returns([ '{"id":"x","created_at":"2026-04-17T00:00:00Z"}', "", @ok_status ])

    @client.add_comment("fizzy-abc", body)
  end

  test "add_comment parses JSON response into Hash" do
    Open3.expects(:capture3).returns([ '{"id":"abc","created_at":"2026-04-17T00:00:00Z","author":"alice@example.com"}', "", @ok_status ])

    result = @client.add_comment("fizzy-abc", "x")
    assert_kind_of Hash, result
    assert_equal "alice@example.com", result["author"]
  end

  # ---- update_description -------------------------------------------

  test "update_description uses bd update --body-file with tempfile content" do
    Open3.expects(:capture3).with do |*argv|
      argv[0] == "bd" &&
        argv[1] == "--actor" &&
        argv[2] == "alice@example.com" &&
        argv[3] == "update" &&
        argv[4] == "fizzy-abc" &&
        argv[5] == "--body-file" &&
        File.read(argv[6]) == "New description body"
    end.returns([ "", "", @ok_status ])

    @client.update_description("fizzy-abc", "New description body")
  end

  test "update_description handles empty plaintext" do
    Open3.expects(:capture3).with do |*argv|
      argv[5] == "--body-file" && File.read(argv[6]) == ""
    end.returns([ "", "", @ok_status ])

    @client.update_description("fizzy-abc", "")
  end
end
