require "test_helper"

class FilterMetadataBoundaryTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
  end

  test "Filter SQL does not reference cards.beads_metadata JSON column" do
    filter = users(:david).filters.new(
      indexed_by: "all",
      sorted_by: "latest",
      board_ids: [ boards(:writebook).id ],
      tag_ids: [ tags(:mobile).id ],
      terms: [ "haggis" ]
    )

    sql = filter.cards.to_sql
    refute_match(/\bbeads_metadata\b/i, sql)
    refute_match(/\bjson_extract\b/i, sql)
  end

  test "Filter implementation does not reference Beads models or metadata accessors" do
    filter_paths = Dir[Rails.root.join("app/models/filter{,/**}/*.rb")]

    code = filter_paths.flat_map { |p| File.read(p).lines }
      .reject { |line| line.lstrip.start_with?("#") }
      .join

    refute_match(/\.beads_metadata\b/, code)
    refute_match(/\bbeads_metadata\b/, code)
    refute_match(/\bBeads::/, code)
    refute_match(/\b:beads\b/, code)
  end
end

