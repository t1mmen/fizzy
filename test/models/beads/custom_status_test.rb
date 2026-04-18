require "test_helper"

class Beads::CustomStatusTest < ActiveSupport::TestCase
  test "creates a custom status with category" do
    cs = Beads::CustomStatus.create!(name: "in_review", category: "unspecified")
    assert_equal "in_review", cs.name
    assert_equal "unspecified", cs.category
  end

  test "name must be present + bounded" do
    assert_not Beads::CustomStatus.new(name: nil, category: "done").valid?
    assert_not Beads::CustomStatus.new(name: "x" * 65, category: "done").valid?
  end

  test "category must be present + bounded" do
    assert_not Beads::CustomStatus.new(name: "x", category: nil).valid?
    assert_not Beads::CustomStatus.new(name: "x", category: "y" * 33).valid?
  end

  test "by_category scope filters" do
    Beads::CustomStatus.create!(name: "shipped", category: "done")
    Beads::CustomStatus.create!(name: "frosted", category: "frozen")

    assert_includes Beads::CustomStatus.done.pluck(:name), "shipped"
    assert_not_includes Beads::CustomStatus.done.pluck(:name), "frosted"
    assert_includes Beads::CustomStatus.frozen_state.pluck(:name), "frosted"
  end

  test "refresh_from upserts from array of hashes" do
    Beads::CustomStatus.refresh_from([
      { name: "first", category: "done" },
      { name: "second", category: "unspecified" }
    ])

    assert_equal 2, Beads::CustomStatus.where(name: %w[ first second ]).count
  end

  test "refresh_from is idempotent (re-running upserts existing)" do
    Beads::CustomStatus.refresh_from([ { name: "stable", category: "done" } ])
    assert_no_difference "Beads::CustomStatus.count" do
      Beads::CustomStatus.refresh_from([ { name: "stable", category: "frozen" } ])
    end
    assert_equal "frozen", Beads::CustomStatus.find("stable").category
  end

  test "refresh_from accepts ducktyped objects (responds_to .name + .category)" do
    row_struct = Struct.new(:name, :category, keyword_init: true)
    Beads::CustomStatus.refresh_from([ row_struct.new(name: "ducked", category: "done") ])
    assert Beads::CustomStatus.exists?(name: "ducked")
  end

  test "KNOWN_CATEGORIES matches P4 §C.1 category enum" do
    assert_equal %w[ done frozen unspecified ], Beads::CustomStatus::KNOWN_CATEGORIES
  end
end
