class TaskPlansController < ApplicationController
  def index
    project = Project.find(params[:project_id])
    plans = project.task_plans.order(:id)
    plans = plans.joins(:tasks).where.not(tasks: { status: "completed" }).distinct unless
      optional_query_boolean(:include_completed)

    render json: { task_plans: plans.map { |plan| serialize_header(plan) } }
  end

  def update
    definitions = params.require(:tasks)
    raise ActionController::BadRequest, "tasks must be an array" unless definitions.is_a?(Array)

    project = Project.find(params[:project_id])
    plan = TaskPlanStore.new.replace!(project:, key: required_string(:key), title: required_string(:title),
      task_definitions: definitions)
    render json: serialize(plan)
  end

  def show
    project = Project.find(params[:project_id])
    render json: serialize(project.task_plans.find_by!(key: required_string(:key)))
  end

  private

  def serialize(plan)
    plan = TaskPlan.includes(tasks: %i[workflow blockers]).find(plan.id)
    {
      task_plan: serialize_header(plan),
      tasks: plan.tasks.order(:id).map do |task|
        task.as_json(only: %i[id key title description_markdown status current_step claim_id version]).merge(
          "workflow" => task.workflow.as_json(only: %i[id key revision]),
          "blocker_keys" => task.blockers.map(&:key).sort
        )
      end
    }
  end

  def serialize_header(plan)
    plan.as_json(only: %i[id project_id key title created_at updated_at])
  end
end
