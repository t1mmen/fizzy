require "action_text"

module Fizzy
  module Beads
    # Per S6 §E.2 + §G: serializes ActionText content (HTML-flavored Trix
    # output) into Beads-compatible plaintext. Used at the controller boundary
    # before invoking CommandClient#add_comment / #update_description.
    #
    # Inline attachments (e.g. <action-text-attachment>) are dropped per S7
    # §C.2 strip-on-write decision — the underlying ActiveStorage rows stay
    # in MySQL but the inline render is lost in Beads.
    #
    # Mention attachments (Action Text mentions like User SGID handles) are
    # best-effort serialized to "@email@example.com" tokens so the S6 §F poller
    # mention parser can re-derive Mentions from the plaintext. If the
    # attachment cannot be resolved to an email, it is dropped silently.
    module ActionTextToPlaintext
      def self.call(value)
        return "" if value.blank?

        content =
          case value
          when ActionText::Content then value
          when ActionText::RichText then value.body
          else ActionText::Content.new(value.to_s)
          end

        # Replace mention attachments with @email tokens before to_plain_text
        # strips them. ActionText::Content#render_attachments yields each
        # attachment to a block; we map mentions to email tokens.
        rendered = content.render_attachments do |attachment|
          mentioned = attachment.try(:node).try(:[], "content-type")
          email = extract_email_from_mention(attachment)
          email ? "@#{email}" : ""
        end

        rendered.to_plain_text
      end

      def self.extract_email_from_mention(attachment)
        # ActionText::Attachment may carry a SGID-resolvable record.
        # Mentions wrap a User (or Identity); Fizzy convention from
        # app/models/concerns/mentions.rb uses Identity#email_address.
        record = attachment.try(:to_attachable) || attachment.try(:attachable)
        return nil unless record

        if record.respond_to?(:email_address)
          record.email_address
        elsif record.respond_to?(:identity) && record.identity.respond_to?(:email_address)
          record.identity.email_address
        end
      end
    end
  end
end
