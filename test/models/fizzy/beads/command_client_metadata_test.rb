require "test_helper"

# S10 F.4: CommandClient#update_fizzy_metadata + #update_prior_status.
# Writes to Beads issues.metadata.fizzy.* JSON bucket atomically (REPLACE
# semantics per S10 §E.1 / fizzy-e5m.1).
class Fizzy::Beads::CommandClientMetadataTest < ActiveSupport::TestCase
  setup do
    @client = Fizzy::Beads::CommandClient.for("alice@example.com", bd_bin: "bd")
    @ok_status = Struct.new(:success?, :exitstatus).new(true, 0)
  end

  test "update_fizzy_metadata composes bd update --metadata with fizzy-namespaced JSON" do
    Open3.expects(:capture3).with do |*argv|
      argv[0..4] == [ "bd", "--actor", "alice@example.com", "update", "fizzy-abc" ] &&
        argv[5] == "--metadata" &&
        JSON.parse(argv[6]) == { "fizzy" => { "prior_status" => "open" } }
    end.returns([ "", "", @ok_status ])

    @client.update_fizzy_metadata("fizzy-abc", prior_status: "open")
  end

  test "update_fizzy_metadata stringifies symbol keys" do
    Open3.expects(:capture3).with do |*argv|
      JSON.parse(argv[6]) == { "fizzy" => { "key1" => "v1", "key2" => "v2" } }
    end.returns([ "", "", @ok_status ])

    @client.update_fizzy_metadata("fizzy-abc", key1: "v1", key2: "v2")
  end

  test "update_fizzy_metadata wraps in top-level fizzy key (does NOT pollute other namespaces)" do
    Open3.expects(:capture3).with do |*argv|
      json = JSON.parse(argv[6])
      json.keys == [ "fizzy" ]
    end.returns([ "", "", @ok_status ])

    @client.update_fizzy_metadata("fizzy-abc", whatever: "x")
  end

  test "update_fizzy_metadata raises ArgumentError on non-Hash input" do
    assert_raises(ArgumentError) do
      @client.update_fizzy_metadata("fizzy-abc", "not-a-hash")
    end
    assert_raises(ArgumentError) do
      @client.update_fizzy_metadata("fizzy-abc", [ :array ])
    end
  end

  test "update_prior_status convenience writes prior_status key under fizzy" do
    Open3.expects(:capture3).with do |*argv|
      JSON.parse(argv[6]) == { "fizzy" => { "prior_status" => "in_progress" } }
    end.returns([ "", "", @ok_status ])

    @client.update_prior_status("fizzy-abc", "in_progress")
  end

  test "update_prior_status accepts symbol status" do
    Open3.expects(:capture3).with do |*argv|
      JSON.parse(argv[6]) == { "fizzy" => { "prior_status" => "deferred" } }
    end.returns([ "", "", @ok_status ])

    @client.update_prior_status("fizzy-abc", :deferred)
  end
end
