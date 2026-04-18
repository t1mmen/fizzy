module Fizzy
  module Beads
    module LabelNormalizer
      class InvalidLabelError < StandardError; end

      def self.call(raw)
        s = raw.to_s.strip.downcase
        raise InvalidLabelError, "label cannot start with #" if s.start_with?("#")
        raise InvalidLabelError, "label cannot be empty" if s.empty?
        s
      end
    end
  end
end
