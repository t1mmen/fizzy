require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "joining an account" do
    account = accounts("37s")

    visit join_url(code: account.join_code.code, script_name: account.slug)
    fill_in "Email address", with: "newbie@example.com"
    click_on "Continue"

    assert_selector "h1", text: "Check your email"
    identity = Identity.find_by!(email_address: "newbie@example.com")
    code = identity.magic_links.active.first.code
    fill_in "code", with: code
    send_keys :enter

    assert_selector "input[id=user_name]"
    assert account.users.find_by!(identity:).verified?, "User was not properly verified"
    fill_in "Full name", with: "New Bee"
    click_on "Continue"

    assert_selector "h1", text: "Writebook"
  end

  test "create a card" do
    sign_in_as(users(:david))

    visit board_url(boards(:writebook))
    click_button "Add a card"
    assert_current_path(%r{/cards/\d+/draft})
    title_field = find("textarea[name='card[title]']")
    title_field.set("Hello, world!")
    title_field.send_keys(:enter) # triggers auto-save submit (keydown.enter->auto-save#submit:prevent)
    fill_in_lexxy with: "I am editing this thing"
    click_on "Create card"

    created = Card.find_by!(title: "Hello, world!")
    visit card_url(created)
    assert_text "Hello, world!"
  end

  test "active storage attachment preview (inline embeds are stripped on Beads write)" do
    sign_in_as(users(:david))

    visit card_url(cards(:layout))
    fill_in_lexxy with: "Here is a comment"
    attach_file file_fixture("moon.jpg") do
      click_on "Upload file"
    end

    within("form lexxy-editor figure.attachment[data-content-type='image/jpeg']") do
      assert_selector "img[src*='/rails/active_storage']"
      assert_selector "figcaption textarea[placeholder='moon.jpg']"
    end

    click_on "Post"

    assert_text "Here is a comment"
    assert_no_selector "action-text-attachment"
  end

  test "dismissing notifications" do
    sign_in_as(users(:david))

    notification = notifications(:logo_mentioned_david)

    assert_selector "div##{dom_id(notification)}"

    within_window(open_new_window) { visit card_url(notification.card) }

    assert_no_selector "div##{dom_id(notification)}"
  end

  test "dragging card to a new column" do
    sign_in_as(users(:david))

    card = cards(:buy_domain)
    target_column = columns(:writebook_in_progress)
    assert_nil(card.column)

    visit board_url(boards(:writebook))

    card_el = page.find("##{dom_id(card, :article)}")
    column_el = page.find("##{dom_id(target_column)}")

    card_el.drag_to(column_el)

    assert_equal "in_progress", card.reload.beads_status
    assert_equal target_column.name, card.projected_column&.name
  end

  private
    def fill_in_lexxy(selector = "lexxy-editor", with:)
      editor_element = find(selector)
      editor_element.set with
      page.execute_script("arguments[0].value = '#{with}'", editor_element)
    end
end
