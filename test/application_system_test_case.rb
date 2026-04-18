require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # System tests must not shell out to `bd` — they run in CI and need to be
  # deterministic and self-contained. Instead, stub the Beads CommandClient
  # and simulate the MySQL mirror side-effects that the S9 poller would
  # normally apply.
  #
  # This is intentionally minimal: it implements only the methods exercised by
  # system test flows (comments, labels, board moves, and status changes).
  class SystemBeadsCommandClient
    def initialize(comment_author:)
      @comment_author = comment_author.to_s
      @comment_seq = 0
    end

    def update_status(_issue_id, _status)
      true
    end

    def add_comment(issue_id, plaintext)
      @comment_seq += 1
      {
        "id" => "beads-comment-system-#{@comment_seq}",
        "issue_id" => issue_id.to_s,
        "author" => current_author,
        "text" => plaintext.to_s,
        "created_at" => Time.current.iso8601
      }
    end

    def add_label(issue_id, label)
      upsert_label(issue_id, label)
    end

    def remove_label(issue_id, label)
      card = Card.find(issue_id.to_s)
      normalized = label.to_s
      tag_ids = Tag.where(account_id: card.account_id, title: normalized).select(:id)
      Tagging.where(account_id: card.account_id, card_id: card.id, tag_id: tag_ids).delete_all
    end

    def move_to_board(issue_id, membership_label)
      normalized = membership_label.to_s
      raise ArgumentError, "membership_label must start with fizzy/board/" unless normalized.start_with?(Board::BOARD_LABEL_PREFIX)

      card = Card.find(issue_id.to_s)

      board_tag_ids = Tag.where(account_id: card.account_id).where("title LIKE ?", "#{Board::BOARD_LABEL_PREFIX}%").select(:id)
      Tagging.where(account_id: card.account_id, card_id: card.id, tag_id: board_tag_ids).delete_all

      upsert_label(issue_id, normalized)
    end

    private
      def upsert_label(issue_id, label)
        card = Card.find(issue_id.to_s)
        normalized = label.to_s
        tag = Tag.find_or_create_by!(account_id: card.account_id, title: normalized)
        Tagging.find_or_create_by!(account_id: card.account_id, card_id: card.id, tag_id: tag.id)
      end

      def current_author
        Current.actor.presence ||
          Current.user&.identity&.email_address.presence ||
          @comment_author
      end
  end

  browser_options = Selenium::WebDriver::Chrome::Options.new.tap do |opts|
    opts.add_argument("--window-size=1200,800")
    opts.add_argument("--disable-extensions")
    # Disable non-foreground tabs from getting a lower process priority
    opts.add_argument("--disable-renderer-backgrounding")
    # Normally, Chrome will treat a 'foreground' tab instead as backgrounded if the surrounding
    # window is occluded (aka visually covered) by another window. This flag disables that.
    opts.add_argument("--disable-backgrounding-occluded-windows")
    # Suppress all permission prompts by automatically denying them.
    opts.add_argument("--deny-permission-prompts")
    opts.add_argument("--enable-automation")
  end

  Capybara.register_driver :chrome_headless do |app|
    browser_options.add_argument("--headless")
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: browser_options)
  end

  Capybara.register_driver :chrome do |app|
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: browser_options)
  end

  if ENV["SYSTEM_TESTS_BROWSER"]
    driven_by :chrome, screen_size: [ 1200, 1000 ]
  else
    driven_by :chrome_headless, screen_size: [ 1200, 1000 ]
  end

  setup do
    # Default stub author to the system actor; per S3/S5/S6 this is always safe
    # fallback and keeps attribution mapping deterministic.
    client = SystemBeadsCommandClient.new(comment_author: SystemActor.email)
    Fizzy::Beads::CommandClient.stubs(:current).returns(client)
  end

  private
    def sign_in_as(user)
      visit session_transfer_url(user.identity.transfer_id, script_name: nil)
      assert_current_path root_path
    end
end
