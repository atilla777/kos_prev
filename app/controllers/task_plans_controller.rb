class TaskPlansController < ApplicationController
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
      task_plan: plan.as_json(only: %i[id project_id key title created_at updated_at]),
      tasks: plan.tasks.order(:id).map do |task|
        task.as_json(only: %i[id key title description_markdown status current_step claim_id version]).merge(
          "workflow" => task.workflow.as_json(only: %i[id key revision]),
          "blocker_keys" => task.blockers.map(&:key).sort
        )
      end
    }
  end
end
