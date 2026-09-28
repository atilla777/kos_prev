class TasksController < ApplicationController
  def ready
    project = Project.find(required_query_integer(:project_id))
    plan = TaskPlan.find(required_query_integer(:task_plan_id)) if params.key?(:task_plan_id)
    raise ActiveRecord::RecordNotFound if plan && plan.project_id != project.id

    render json: { tasks: lifecycle.ready(project:, task_plan: plan).map { |task| serialize_task(task) } }
  end

  def show
    render json: { task: serialize_task(Task.find(params[:id])) }
  end

  def context
    task = Task.includes(task_plan: :project).includes(:workflow).find(params[:id])
    step = task.workflow.step_for(task.current_step)
    render json: {
      task: serialize_task(task).merge("description_markdown" => task.description_markdown),
      task_plan: task.task_plan.as_json(only: %i[id project_id key title]),
      project: task.task_plan.project.as_json(only: %i[id name repository_identity remote_url default_branch]),
      workflow: task.workflow.as_json(only: %i[id key revision]),
      step: step.slice("id", "name", "instruction", "outcomes").merge(
        "allowed_outcomes" => step.fetch("outcomes").keys
      ),
      results: task.accepted_results.map { |result_step, value| { "step" => result_step, "outcome" => value["outcome"] } },
      pause: pause_for(task)
    }
  end

  def result
    task = Task.find(params[:id])
    accepted = task.accepted_results[required_query_string(:step)]
    raise ActiveRecord::RecordNotFound unless accepted

    render json: accepted
  end

  def claim
    task = lifecycle.claim!(task_id: params[:id], claim_id: required_string(:claim_id),
      version: required_integer(:version))
    render json: { task: serialize_task(task) }
  end

  def takeover
    task = lifecycle.takeover!(task_id: params[:id], claim_id: required_string(:claim_id),
      version: required_integer(:version), step: required_string(:step))
    render json: { task: serialize_task(task) }
  end

  def report
    task = lifecycle.report!(task_id: params[:id], claim_id: required_string(:claim_id),
      version: required_integer(:version), step: required_string(:step), outcome: required_string(:outcome),
      result: required_text(:result), message: optional_string(:message))
    render json: { task: serialize_task(task) }
  end

  def answer
    task = lifecycle.answer!(task_id: params[:id], version: required_integer(:version),
      step: required_string(:step), answer: required_text(:answer))
    render json: { task: serialize_task(task) }
  end

  private

  def required_query_string(name)
    value = params.require(name)
    raise ActionController::BadRequest, "#{name} must be a non-empty string" unless value.is_a?(String) && value.present?

    value
  end

  def lifecycle
    @lifecycle ||= TaskLifecycle.new
  end

  def serialize_task(task)
    task.as_json(only: %i[id task_plan_id workflow_id key title status current_step claim_id version pause_kind
      pause_message pause_step answer created_at updated_at]).merge("blocker_ids" => task.blocker_ids.sort)
  end

  def pause_for(task)
    return unless task.pause_step

    { kind: task.pause_kind, step: task.pause_step, message: task.pause_message, answer: task.answer }
  end
end
