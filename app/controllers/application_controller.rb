class ApplicationController < ActionController::API
  rescue_from ActionController::BadRequest, ActionController::ParameterMissing,
    ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_validation_failed
  rescue_from ActiveRecord::RecordNotUnique, with: :render_record_not_unique
  rescue_from RepositoryIdentity::Invalid, with: :render_bad_request
  rescue_from TaskLifecycle::InvalidTransition, with: :render_invalid_transition
  rescue_from TaskLifecycle::InvalidInput, with: :render_bad_request
  rescue_from TaskLifecycle::Conflict, with: :render_conflict
  rescue_from TaskPlanStore::InvalidDefinition, with: :render_bad_request

  before_action :authenticate_api_token

  private

  def required_string(name, max_bytes: CoordinationLimits::MAX_KEY_BYTES)
    value = params.require(name)
    unless CoordinationLimits.valid_text?(value, max_bytes:)
      raise ActionController::BadRequest, "#{name} must be a non-empty valid UTF-8 string of at most #{max_bytes} bytes"
    end

    value
  end

  def required_integer(name)
    value = params.require(name)
    raise ActionController::BadRequest, "#{name} must be an integer" unless value.is_a?(Integer)

    value
  end

  def required_text(name, max_bytes: CoordinationLimits::MAX_TEXT_BYTES)
    value = params.require(name)
    raise ActionController::BadRequest, "#{name} must be a non-empty valid UTF-8 string" unless
      value.is_a?(String) && !value.empty? && value.encoding == Encoding::UTF_8 && value.valid_encoding?
    raise ActionController::BadRequest, "#{name} must be at most #{max_bytes} bytes" if value.bytesize > max_bytes

    value
  end

  def optional_string(name, max_bytes: CoordinationLimits::MAX_TEXT_BYTES)
    return unless params.key?(name)

    value = params[name]
    unless value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding? && value.bytesize <= max_bytes
      raise ActionController::BadRequest, "#{name} must be a valid UTF-8 string of at most #{max_bytes} bytes"
    end

    value
  end

  def optional_integer(name)
    return unless params.key?(name)

    value = params[name]
    return if value.nil?
    raise ActionController::BadRequest, "#{name} must be an integer or null" unless value.is_a?(Integer)

    value
  end

  def required_query_integer(name)
    value = params.require(name)
    Integer(value, 10)
  rescue ArgumentError, TypeError
    raise ActionController::BadRequest, "#{name} must be an integer"
  end

  def optional_query_boolean(name, default: false)
    return default unless params.key?(name)

    return true if params[name] == "true"
    return false if params[name] == "false"

    raise ActionController::BadRequest, "#{name} must be true or false"
  end

  def optional_integer_array(name, default: nil)
    return default unless params.key?(name)

    value = params[name]
    unless value.is_a?(Array) && value.all? { |item| item.is_a?(Integer) }
      raise ActionController::BadRequest, "#{name} must be an array of integers"
    end

    value
  end

  def authenticate_api_token
    scheme, token = request.authorization.to_s.split(" ", 2)
    expected_token = Rails.application.config.x.kos.api_token

    return if scheme&.casecmp?("Bearer") && token.present? &&
      ActiveSupport::SecurityUtils.secure_compare(token, expected_token)

    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def render_bad_request(error)
    render json: { error: "bad_request", message: error.message }, status: :bad_request
  end

  def not_found!(resource, lookup)
    description = lookup.map { |key, value| "#{key}=#{value.inspect}" }.join(" and ")
    raise ActiveRecord::RecordNotFound, "#{resource} not found for #{description}"
  end

  def render_not_found(error)
    render json: { error: "not_found", message: error.message }, status: :not_found
  end

  def render_validation_failed(error)
    render json: { error: "validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
  end

  def render_record_not_unique
    render json: { error: "conflict", message: "a unique value is already in use" }, status: :conflict
  end

  def render_invalid_transition(error)
    render json: { error: "invalid_transition", message: error.message }, status: :unprocessable_entity
  end

  def render_conflict(error)
    render json: { error: "conflict", message: error.message }, status: :conflict
  end
end
