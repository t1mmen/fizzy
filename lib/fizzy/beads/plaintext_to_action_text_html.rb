require "action_view"

module Fizzy
  module Beads
    # Per S6 §A.3 + §D.2: converts Beads plaintext (issues.description /
    # comments.text) into ActionText-compatible HTML for rendering as the
    # derived cache. Used by the S9 poller's mirror procedures.
    #
    # V1 formatting is intentionally minimal:
    #   - HTML-escape the plaintext
    #   - Wrap paragraphs in <p>...</p> (newline-separated)
    #   - Convert single newlines to <br>
    #   - No attachments / embeds (S7 §C — attachments are Fizzy-only and not
    #     reconstructed from plaintext markers)
    module PlaintextToActionTextHtml
      include ActionView::Helpers::TextHelper
      include ActionView::Helpers::OutputSafetyHelper
      extend self

      def call(plaintext)
        return "" if plaintext.blank?
        # Escape first (XSS prevention), then format with sanitize: false so
        # simple_format doesn't try to sanitize already-safe escaped output.
        escaped = ERB::Util.html_escape(plaintext.to_s)
        simple_format(escaped, {}, sanitize: false, wrapper_tag: "p").to_s
      end
    end
  end
end
