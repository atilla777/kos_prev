module Kos
  module ApiToken
    module_function

    def normalize(value)
      return unless value.is_a?(String)

      token = value.b.dup.force_encoding(Encoding::UTF_8)
      token if token.valid_encoding? && !token.empty? && token == token.strip && !token.match?(/[\x00-\x1f\x7f]/)
    end
  end
end
