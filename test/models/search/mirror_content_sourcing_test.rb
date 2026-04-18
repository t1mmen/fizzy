require "test_helper"

# S9 F.12 (fizzy-pmi.12): audit that the poller mirror procedures call
# Search::Record.upsert! with the right content for every Card and
# (eventual) Comment mirror.
class Search::MirrorContentSourcingTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    Rails.application.config.x.fizzy.install_hostname = "test.fizzy.localhost"
    @account = accounts("37s")
    @board = boards(:writebook)
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = nil
  end

  test "IssueMirror.call writes a Search::Record row keyed by the Card id" do
    Beads::Mirror::IssueMirror.call(
      { id: "fizzy-search-001", status: "open", title: "Searchable Card" },
      account_id: @account.id, board_id: @board.id, creator_id: users(:david).id
    )

    record = Search::Record.find_by(searchable_type: "Card", searchable_id: "fizzy-search-001")
    assert_not_nil record, "expected a Search::Record row to be upserted by IssueMirror"
    assert_equal @account.id, record.account_id
    assert_equal @board.id, record.board_id
    assert_equal "fizzy-search-001", record.card_id
  end

  test "Search::Record content includes title + beads_status (per S9 §F.2)" do
    Beads::Mirror::IssueMirror.call(
      { id: "fizzy-search-002", status: "in_progress", title: "Title here" },
      account_id: @account.id, board_id: @board.id, creator_id: users(:david).id
    )

    record = Search::Record.find_by(searchable_type: "Card", searchable_id: "fizzy-search-002")
    assert_not_nil record
    assert_includes record.content, "Title here", "Search::Record.content must include the Card title"
    assert_includes record.content, "in_progress", "Search::Record.content must include the beads_status"
  end

  test "IssueMirror is idempotent (re-mirror updates content, doesn't duplicate Search::Record)" do
    Beads::Mirror::IssueMirror.call(
      { id: "fizzy-search-003", status: "open", title: "Original" },
      account_id: @account.id, board_id: @board.id, creator_id: users(:david).id
    )
    initial_record_id = Search::Record.find_by(searchable_id: "fizzy-search-003").id

    assert_no_difference "Search::Record.count" do
      Beads::Mirror::IssueMirror.call(
        { id: "fizzy-search-003", status: "closed", title: "Updated" },
        account_id: @account.id, board_id: @board.id, creator_id: users(:david).id
      )
    end

    record = Search::Record.find(initial_record_id)
    assert_includes record.content, "Updated"
    assert_includes record.content, "closed"
  end

  test "Search::Record.upsert! signature accepts the mirror procedure shape" do
    # Mirror the Card first so the FK validation passes
    Beads::Mirror::IssueMirror.call(
      { id: "fizzy-search-direct", status: "open", title: "Direct upsert prep" },
      account_id: @account.id, board_id: @board.id, creator_id: users(:david).id
    )
    record = Search::Record.upsert!(
      account_id: @account.id,
      searchable_type: "Card",
      searchable_id: "fizzy-search-direct",
      card_id: "fizzy-search-direct",
      board_id: @board.id,
      title: "Direct upsert",
      content: "Direct content",
      created_at: Time.current
    )
    assert_not_nil record
  end

  test "Search::Record uses the default AR connection (16-shard FTS in prod; single in SQLite)" do
    # S9 §F.1 + §F.3: Search::Record.search route is preserved on the
    # default connection. Should NOT be on a :beads connection.
    assert_equal ApplicationRecord.connection_pool, Search::Record.connection_pool
  end

  test "Searchable::SEARCH_CONTENT_LIMIT is honored when content is computed (32 kilobytes per Searchable concern)" do
    # IssueMirror's content is short (title + status), but the concern's
    # truncate_bytes(SEARCH_CONTENT_LIMIT) governs Comment mirror per S9 §F.2.
    # This test guards against the constant being changed without updating
    # the mirror procedures' content sourcing.
    assert_equal 32.kilobytes, Searchable::SEARCH_CONTENT_LIMIT
  end

  # ----- CommentMirror.call (S9 F.6 / pmi.6) Search::Record sourcing -----

  test "CommentMirror.call writes a Search::Record row keyed by the Comment id" do
    Beads::Mirror::IssueMirror.call(
      { id: "fizzy-cmt-001", status: "open", title: "Card with comments" },
      account_id: @account.id, board_id: @board.id, creator_id: users(:david).id
    )
    comment_id = SecureRandom.uuid
    Beads::Mirror::CommentMirror.call(
      { id: comment_id, issue_id: "fizzy-cmt-001", text: "Searchable comment body", created_at: Time.current, author: users(:david).identity.email_address },
      account_id: @account.id
    )

    record = Search::Record.find_by(searchable_type: "Comment", searchable_id: comment_id)
    assert_not_nil record, "expected a Search::Record row to be upserted by CommentMirror"
    assert_equal "fizzy-cmt-001", record.card_id
    assert_equal @board.id, record.board_id
    assert_includes record.content, "Searchable comment body"
  end

  test "CommentMirror is idempotent (replay updates content, doesn't duplicate Search::Record)" do
    Beads::Mirror::IssueMirror.call(
      { id: "fizzy-cmt-002", status: "open", title: "Card with comments" },
      account_id: @account.id, board_id: @board.id, creator_id: users(:david).id
    )
    comment_id = SecureRandom.uuid
    Beads::Mirror::CommentMirror.call(
      { id: comment_id, issue_id: "fizzy-cmt-002", text: "Original", created_at: Time.current, author: users(:david).identity.email_address },
      account_id: @account.id
    )

    assert_no_difference "Search::Record.count" do
      Beads::Mirror::CommentMirror.call(
        { id: comment_id, issue_id: "fizzy-cmt-002", text: "Updated", created_at: Time.current, author: users(:david).identity.email_address },
        account_id: @account.id
      )
    end

    record = Search::Record.find_by(searchable_type: "Comment", searchable_id: comment_id)
    assert_includes record.content, "Updated"
  end

  # ----- Shard routing (S9 §F.3): CRC32(account_id) % 16 -----

  test "shard routing algorithm is CRC32(account_id) % 16 (Trilogy/MySQL prod path)" do
    # The 16-shard FTS pattern is preserved in production. In SQLite dev/test
    # Search::Record uses a single table, but the Trilogy concern exposes
    # `shard_id_for_account` for the prod path; assert its algorithm.
    sample_account_id = "03ayaunetv3z4n681d58wdysd"
    sharded = Class.new(ApplicationRecord) { include Search::Record::Trilogy }
    expected_shard = Zlib.crc32(sample_account_id) % 16
    assert_equal expected_shard, sharded.shard_id_for_account(sample_account_id)
    assert (0..15).cover?(expected_shard), "shard id must be in [0..15]"
    assert_equal Search::Record::Trilogy::SHARD_COUNT, 16
  end

  # ----- Search::Record.search returns mirrored content within one tick -----

  test "Search::Record.search returns the freshly-mirrored Card content within one tick" do
    Beads::Mirror::IssueMirror.call(
      { id: "fizzy-srch-card", status: "open", title: "Searchable just-mirrored title XYZ" },
      account_id: @account.id, board_id: @board.id, creator_id: users(:david).id
    )

    user = users(:david)
    results = Search::Record.search("XYZ", user: user)
    titles = results.to_a.map(&:title)
    assert titles.any? { |t| t.to_s.include?("XYZ") }, "expected freshly mirrored Card to surface in Search::Record.search results"
  end
end
