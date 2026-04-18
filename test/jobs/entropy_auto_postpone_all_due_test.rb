require "test_helper"

class EntropyAutoPostponeAllDueTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    @previous_install_hostname = Rails.application.config.x.fizzy.install_hostname
    Rails.application.config.x.fizzy.install_hostname = "test.local"
  end

  teardown do
    Rails.application.config.x.fizzy.install_hostname = @previous_install_hostname
  end

  test "auto_postpone_all_due defers with system actor and does not leak Current.actor" do
    freeze_time

    card = cards(:logo)
    Card.stubs(:due_to_be_postponed).returns(Card.where(id: card.id))

    original_actor = "kevin@example.com"
    Current.actor = original_actor

    until_time = (Time.current + card.auto_postpone_period.to_i).iso8601
    status = stub(success?: true, exitstatus: 0)

    Open3.expects(:capture3)
      .with("bd", "--actor", "system@test.local", "defer", card.id.to_s, "--until=#{until_time}")
      .returns(["", "", status])

    Card.auto_postpone_all_due

    assert_equal original_actor, Current.actor
  end
end
