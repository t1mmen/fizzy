require "open3"
require "json"
require "tempfile"
require "fizzy/beads/label_normalizer"
require "fizzy/beads/reserved_namespace"

module Fizzy
  module Beads
    class CommandClient
      class MissingActorError < StandardError; end

      class CommandError < StandardError
        attr_reader :argv, :status, :stderr

        def initialize(argv:, status:, stderr:)
          @argv = argv
          @status = status
          @stderr = stderr

          exit_status = status&.respond_to?(:exitstatus) ? status.exitstatus : "unknown"
          super("bd command failed (status=#{exit_status}): #{argv.join(" ")}\n#{stderr}".strip)
        end
      end

      def self.for(identity_or_actor, bd_bin: "bd")
        actor =
          case identity_or_actor
          when Identity
            identity_or_actor.email_address
          when String
            identity_or_actor
          when nil
            raise MissingActorError, "actor is required"
          else
            raise ArgumentError, "unsupported actor type: #{identity_or_actor.class}"
          end

        new(actor:, bd_bin:)
      end

      def self.current(bd_bin: "bd")
        actor = Current.actor
        raise MissingActorError, "Current.actor is not set" if actor.blank?

        new(actor:, bd_bin:)
      end

      def initialize(actor:, bd_bin: "bd")
        raise MissingActorError, "actor is required" if actor.blank?

        @actor = actor
        @bd_bin = bd_bin
      end

      # ------------------------------------------------------------------
      # S4 F.1 — lifecycle methods (per S4 §A + §B.1)
      # NOTE: Ruby cannot accept a keyword named `until:` directly (reserved),
      # but callers may still pass `until:`; we accept it via **kwargs.
      # ------------------------------------------------------------------

      def update_status(id, status)
        invoke!([ "update", id.to_s, "--status", status.to_s ])
      end

      def close_issue(id, reason: nil)
        argv = [ "close", id.to_s ]
        argv.concat([ "--reason", reason.to_s ]) if reason.present?
        invoke!(argv)
      end

      def reopen_issue(id, reason: nil, restore_status: nil)
        argv = [ "reopen", id.to_s ]
        argv.concat([ "--reason", reason.to_s ]) if reason.present?
        invoke!(argv)

        update_status(id, restore_status) if restore_status.present?
      end

      def defer_issue(id, until_time: nil, **kwargs)
        until_time ||= kwargs[:until]
        argv = [ "defer", id.to_s ]
        argv << "--until=#{until_time}" if until_time.present?
        invoke!(argv)
      end

      def undefer_issue(id, restore_status: nil)
        invoke!([ "undefer", id.to_s ])
        update_status(id, restore_status) if restore_status.present?
      end

      def update_defer_until(id, until_time: nil, **kwargs)
        until_time ||= kwargs[:until]
        raise ArgumentError, "until_time is required" if until_time.blank?

        invoke!([ "update", id.to_s, "--defer", until_time.to_s ])
      end

      def read_issue(id)
        JSON.parse(invoke!([ "--json", "show", id.to_s ]).to_s)
      end

      # ------------------------------------------------------------------
      # S5 F.3 — label methods (per S5 §A.2 + §C.1)
      # Reject reserved fizzy/ namespace; system code paths use the private
      # _add_system_label / _remove_system_label methods (S5 F.5 / fizzy-75i).
      # ------------------------------------------------------------------

      def add_label(id, label)
        normalized = LabelNormalizer.call(label)
        raise ArgumentError, "label '#{normalized}' uses reserved namespace fizzy/" if ReservedNamespace.violates?(normalized)
        invoke!([ "update", id.to_s, "--add-label", normalized ])
      end

      def remove_label(id, label)
        normalized = LabelNormalizer.call(label)
        invoke!([ "update", id.to_s, "--remove-label", normalized ])
      end

      def set_labels(id, labels)
        normalized = Array(labels).map { |l| LabelNormalizer.call(l) }
        normalized.each do |l|
          raise ArgumentError, "label '#{l}' uses reserved namespace fizzy/" if ReservedNamespace.violates?(l)
        end
        invoke!([ "update", id.to_s, "--set-labels", normalized.join(",") ])
      end

      # ------------------------------------------------------------------
      # S5 F.4 — set_assignee (per S5 §C.1 + §F.3)
      # email may be nil/empty to clear the Beads assignee.
      # ------------------------------------------------------------------

      def set_assignee(id, email_or_nil)
        value = email_or_nil.to_s
        invoke!([ "update", id.to_s, "--assignee", value ])
      end

      # ------------------------------------------------------------------
      # S5 F.5 — system label methods (per S5 §C.4)
      # Internal-only: callable from Fizzy system code paths that
      # legitimately write fizzy/-prefixed labels (Board create/move via
      # S2; future system label managers). NOT exposed to controllers
      # (which use add_label/set_labels with the fizzy/ guard).
      # ------------------------------------------------------------------

      def _add_system_label(id, label)
        normalized = LabelNormalizer.call(label)
        invoke!([ "update", id.to_s, "--add-label", normalized ])
      end

      def _remove_system_label(id, label)
        normalized = LabelNormalizer.call(label)
        invoke!([ "update", id.to_s, "--remove-label", normalized ])
      end

      # ------------------------------------------------------------------
      # S6 F.2 — add_comment (per S6 §C.1 + §C.2)
      # Uses --file to avoid quoting/escaping pitfalls; --author = @actor
      # so poller deterministic mapping works (S6 §C.3); --json so we get
      # the created comment id+created_at back.
      # Returns parsed Hash with at minimum "id" and "created_at" keys.
      # ------------------------------------------------------------------

      def add_comment(issue_id, plaintext)
        with_tempfile(plaintext) do |path|
          stdout = invoke!([ "comments", "add", issue_id.to_s, "--file", path, "--author", @actor, "--json" ])
          JSON.parse(stdout.to_s.strip)
        end
      end

      # ------------------------------------------------------------------
      # S6 F.3 — update_description (per S6 §C.1 + §G)
      # Uses --body-file (preferred for multi-line plaintext per S10 §D.1
      # write protocol). For short single-line strings the caller could use
      # --description directly; we prefer the file form universally.
      # ------------------------------------------------------------------

      def update_description(issue_id, plaintext)
        with_tempfile(plaintext) do |path|
          invoke!([ "update", issue_id.to_s, "--body-file", path ])
        end
      end

      private

      def with_tempfile(content)
        Tempfile.create([ "fizzy_beads_", ".txt" ]) do |f|
          f.write(content.to_s)
          f.flush
          yield f.path
        end
      end

      def invoke!(argv)
        full_argv = [@bd_bin, "--actor", @actor, *argv]
        stdout, stderr, status = Open3.capture3(*full_argv)

        raise CommandError.new(argv: full_argv, status:, stderr:) unless status.success?

        stdout
      rescue Errno::ENOENT => e
        raise CommandError.new(argv: full_argv, status: nil, stderr: e.message)
      end
    end
  end
end
