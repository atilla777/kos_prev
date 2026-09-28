class BoundedTextValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.nil?
    return if value.is_a?(String) && value.valid_encoding? &&
      (value.encoding == Encoding::UTF_8 || value.ascii_only?) && value.bytesize <= options.fetch(:maximum)

    record.errors.add(attribute, "must be valid UTF-8 and at most #{options.fetch(:maximum)} bytes")
  end
end
