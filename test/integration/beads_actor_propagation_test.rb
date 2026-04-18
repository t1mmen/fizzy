require "test_helper"

class TestUnauthenticatedBeadsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_account

  def show
    Fizzy::Beads::CommandClient.current.update_status("fizzy-test-unauth-001", "open")
    head :no_content
  end
end

class BeadsActorPropagationTest < ActionDispatch::IntegrationTest

  setup do
    @card = cards(:logo)
  end

  test "authenticated cookie session request carries --actor <identity.email_address> to bd argv" do
    sign_in_as :david
    expected_actor = identities(:david).email_address

    captured_argvs = []
    ok_status = stub(success?: true, exitstatus: 0)

    Open3.stubs(:capture3).with do |*argv|
      captured_argvs << argv
      true
    end.returns([ "", "", ok_status ])

    post card_closure_path(@card, format: :json)
    assert_response :no_content

    assert captured_argvs.any? { |argv| argv.include?("--actor") && argv.include?(expected_actor) },
      "expected at least one bd invocation to include --actor #{expected_actor}, got:\n#{captured_argvs.map(&:join).join("\n")}"
  end

  test "bearer token request carries --actor <token identity email> to bd argv" do
    bearer = { "HTTP_AUTHORIZATION" => "Bearer #{identity_access_tokens(:davids_api_token).token}" }
    expected_actor = identities(:david).email_address

    captured_argvs = []
    ok_status = stub(success?: true, exitstatus: 0)

    Open3.stubs(:capture3).with do |*argv|
      captured_argvs << argv
      true
    end.returns([ "", "", ok_status ])

    post card_closure_path(@card, format: :json), env: bearer
    assert_response :no_content

    assert captured_argvs.any? { |argv| argv.include?("--actor") && argv.include?(expected_actor) },
      "expected at least one bd invocation to include --actor #{expected_actor}, got:\n#{captured_argvs.map(&:join).join("\n")}"
  end

  test "allow_unauthenticated_access controller calling CommandClient.current raises MissingActorError" do
    with_routing do |set|
      set.draw do
        get "/test/unauthenticated/beads", to: "test_unauthenticated_beads#show"
      end

      assert_raises(Fizzy::Beads::CommandClient::MissingActorError) do
        get "/test/unauthenticated/beads"
      end
    end
  end
end
