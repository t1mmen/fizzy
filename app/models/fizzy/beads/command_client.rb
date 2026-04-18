require "open3"

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

      private

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

