class ReadinessController < ApplicationController
  skip_before_action :authenticate_api_token

  def show
    ReadinessCheck.call
    render json: identity.merge(status: "ready")
  rescue ReadinessCheck::Error => error
    Rails.logger.error("KOS readiness failed component=#{error.component} error=#{error.cause&.class || error.class}")
    render json: identity.merge(status: "unavailable"), status: :service_unavailable
  end

  private

  def identity
    { version: Kos::VERSION, source_id: Rails.application.config.x.kos.source_id }
  end
end
