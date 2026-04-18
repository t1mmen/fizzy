require "test_helper"

# S5 §J.5 (fizzy-ehj): TagDeletionJob iterates every Beads-id card holding
# a label, removes it via CommandClient, then destroys the Tag row.
class TagDeletionJobTest < ActiveJob::TestCase
  setup do
    Current.session = sessions(:david)
    Current.actor = "david@37signals.com"
    Rails.application.config.x.fizzy.install_hostname = "test.fizzy.localhost"

    @account = accounts("37s")
    @board = boards(:writebook)
    @user = users(:david)
    @tag = @account.tags.create!(title: "doomed")
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = nil
    Current.actor = nil
  end

  test "invokes CommandClient.remove_label once per Beads-id card carrying the label, then destroys the Tag" do
    card_a = beads_card!("fizzy-ehj-a-#{SecureRandom.hex(4)}")
    card_b = beads_card!("fizzy-ehj-b-#{SecureRandom.hex(4)}")
    card_a.taggings.create!(tag: @tag)
    card_b.taggings.create!(tag: @tag)

    Fizzy::Beads::CommandClient.any_instance.expects(:remove_label).with(card_a.id, "doomed").once
    Fizzy::Beads::CommandClient.any_instance.expects(:remove_label).with(card_b.id, "doomed").once

    assert_difference "Tag.count", -1 do
      TagDeletionJob.perform_now(@tag)
    end
  end

  test "skips CommandClient hop for legacy uuid-id cards (no Beads issue)" do
    uuid_card = cards(:logo)
    uuid_card.taggings.create!(tag: @tag) unless uuid_card.tagged_with?(@tag)

    Fizzy::Beads::CommandClient.any_instance.expects(:remove_label).never

    assert_difference "Tag.count", -1 do
      TagDeletionJob.perform_now(@tag)
    end
  end

  test "is idempotent when CommandClient raises (label already absent on remote)" do
    card = beads_card!("fizzy-ehj-c-#{SecureRandom.hex(4)}")
    card.taggings.create!(tag: @tag)

    Fizzy::Beads::CommandClient.any_instance.stubs(:remove_label).raises(StandardError, "label not found")

    assert_difference "Tag.count", -1 do
      assert_nothing_raised { TagDeletionJob.perform_now(@tag) }
    end
  end

  test "destroys the Tag even when no cards reference it" do
    assert_difference "Tag.count", -1 do
      TagDeletionJob.perform_now(@tag)
    end
  end

  private
    def beads_card!(id)
      @board.cards.create!(id: id, title: "Beads card #{id}", creator: @user)
    end
end
