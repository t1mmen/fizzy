require "test_helper"

# S9 F.11 (fizzy-pmi.11): audit that Filter compilation never reaches the
# :beads database connection. Every supported operator must compile to
# Card mirror SQL only — per S9 §E + S10 §A.2 #2 invariant.
class Filter::NoBeadsConnectionAuditTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    @account = accounts("37s")
    @board = boards(:writebook)
    @user = users(:david)
  end

  test "Filter::Resources only references AR models on the default connection" do
    # All Filter sidecar associations: tags, assignees, creators, closers,
    # boards, cards. They must all be AR models on the same connection as
    # ApplicationRecord (the default; not :beads).
    default_conn_pool = ApplicationRecord.connection_pool
    [ Tag, User, Board, Card ].each do |model|
      assert_equal default_conn_pool, model.connection_pool,
        "#{model} must use the default AR connection pool — Filter compilation must not reach :beads"
    end
  end

  test "no Filter source file references :beads connection" do
    # Static check: grep -r ':beads' app/models/filter*.rb returns nothing.
    filter_files = Dir["app/models/filter.rb", "app/models/filter/**/*.rb"]
    refute filter_files.empty?, "expected to find Filter source files"

    filter_files.each do |path|
      content = File.read(path)
      refute_match(/:beads\b/, content,
        "#{path} must not reference the :beads connection (S9 §E.2 invariant)")
      refute_match(/connects_to.*beads/i, content,
        "#{path} must not connect to a Beads-side database")
    end
  end

  test "cards(beads_status) index exists for status filter" do
    indexes = ActiveRecord::Base.connection.indexes(:cards).map(&:name)
    assert_includes indexes, "index_cards_on_beads_status",
      "expected cards.beads_status index per S9 §E.3 (status filter performance)"
  end

  test "taggings(card_id, tag_id) unique index exists for tag filter" do
    indexes = ActiveRecord::Base.connection.indexes(:taggings)
    composite = indexes.find { |i| i.columns == [ "card_id", "tag_id" ] }
    assert_not_nil composite, "expected taggings(card_id, tag_id) index per S9 §E.3"
    assert composite.unique, "expected the (card_id, tag_id) index to be UNIQUE"
  end

  test "assignments(assignee_id, card_id) unique index exists for assignee filter" do
    indexes = ActiveRecord::Base.connection.indexes(:assignments)
    composite = indexes.find { |i| i.columns == [ "assignee_id", "card_id" ] }
    assert_not_nil composite, "expected assignments(assignee_id, card_id) index per S9 §E.3"
    assert composite.unique
  end

  test "Search::Record (FTS) is queryable via the default connection" do
    # Sanity check: Search::Record uses the same connection as ApplicationRecord
    # (sharded MySQL FTS in prod; single search_records table in SQLite dev).
    # No :beads connection involved.
    assert_equal ApplicationRecord.connection_pool, Search::Record.connection_pool
  end
end
