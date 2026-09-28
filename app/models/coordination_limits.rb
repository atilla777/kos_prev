module CoordinationLimits
  MAX_KEY_BYTES = 100
  MAX_NAME_BYTES = 200
  MAX_TEXT_BYTES = 16.kilobytes
  MAX_URL_BYTES = 2.kilobytes
  MAX_CLAIM_ID_BYTES = 200
  MAX_TASKS_PER_PLAN = 64
  MAX_DEPENDENCIES_PER_PLAN = 256
  MAX_STEPS_PER_WORKFLOW = 64
  MAX_OUTCOMES_PER_WORKFLOW = 256
  MAX_RESULT_BYTES = 1.megabyte
  MAX_ACCEPTED_RESULTS_BYTES = 4.megabytes
  MAX_REQUEST_BODY_BYTES = 8.megabytes

  def self.valid_text?(value, max_bytes:, allow_blank: false)
    value.is_a?(String) && value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.ascii_only?) &&
      (allow_blank || value.present?) && value.bytesize <= max_bytes
  end
end
