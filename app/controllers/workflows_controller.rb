class WorkflowsController < ApplicationController
  def index
    workflows = Workflow.order(:key, :revision)
    workflows = workflows.where(key: required_string(:key, max_bytes: CoordinationLimits::MAX_KEY_BYTES)) if params.key?(:key)
    render json: { workflows: workflows.map { |workflow| serialize(workflow) } }
  end

  def show
    render json: { workflow: serialize(Workflow.find(params[:id])) }
  end

  def create
    definition = params.require(:definition_json)
    unless definition.is_a?(ActionController::Parameters)
      raise ActionController::BadRequest, "definition_json must be an object"
    end

    key = required_string(:key, max_bytes: CoordinationLimits::MAX_KEY_BYTES)
    workflow = Workflow.transaction do
      revision = Workflow.where(key:).maximum(:revision).to_i + 1
      Workflow.create!(key:, name: required_string(:name, max_bytes: CoordinationLimits::MAX_NAME_BYTES), revision:,
        definition_json: definition.to_unsafe_h)
    end

    render json: { workflow: serialize(workflow) }, status: :created
  end


  private

  def serialize(workflow)
    workflow.as_json(only: %i[id key name revision definition_json created_at])
  end
end
