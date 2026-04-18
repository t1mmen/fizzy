require "fizzy/beads/label_normalizer"

module Fizzy
  module Beads
    module ReservedNamespace
      RESERVED_PREFIX_RE = %r{\Afizzy/}i

      def self.violates?(label)
        Fizzy::Beads::LabelNormalizer.call(label).match?(RESERVED_PREFIX_RE)
      rescue Fizzy::Beads::LabelNormalizer::InvalidLabelError
        false
      end
    end
  end
end
