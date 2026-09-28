class StatusesController < ApplicationController
  def show
    payload = ApplicationRecord.transaction do
      identity = required_string(:repository_identity, max_bytes: CoordinationLimits::MAX_URL_BYTES)
      project = Project.find_by(repository_identity: identity)
      unless project
        raise ActiveRecord::RecordNotFound,
          "Project is not registered under #{identity.inspect}; register it with `kos project create` first."
      end

      RecoveryStatus.new(project).as_json
    end

    render json: payload
  end
end
