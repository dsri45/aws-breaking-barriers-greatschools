class HealthController < ApplicationController
  def ready
    ApplicationRecord.with_connection { |connection| connection.select_value("SELECT 1") }
    render json: { status: "ready" }
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("Readiness database check failed (#{error.class})")
    render json: { status: "unavailable" }, status: :service_unavailable
  end
end
