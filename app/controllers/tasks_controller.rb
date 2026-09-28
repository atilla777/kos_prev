class TasksController < ApplicationController
  def index
    project = Project.find(params[:project_id])
    tasks = project.tasks.includes(:blockers, :workflow).order(:id)
    tasks = tasks.where.not(status: "completed") unless optional_query_boolean(:include_completed)

    render json: { tasks: tasks.map { |task| serialize_task(task) } }
  end

  def ready
    project = Project.find(required_query_integer(:project_id))
    if params.key?(:task_plan_id)
      task_plan_id = required_query_integer(:task_plan_id)
      plan = project.task_plans.find_by(id: task_plan_id) || not_found!("Task plan", id: task_plan_id,
        project_id: project.id)
    end

    render json: { tasks: lifecycle.ready(project:, task_plan: plan).includes(:workflow).map { |task| serialize_task(task) } }
  end

  def show
    render json: { task: serialize_task(find_task) }
  end

  def context
    task = Task.includes(task_plan: :project).includes(:workflow).find(params[:id])
    step = task.workflow.step_for(task.current_step)
    render json: {
      task: serialize_task(task).merge("description_markdown" => task.description_markdown),
      task_plan: task.task_plan.as_json(only: %i[id project_id key title status version]),
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
    task = find_task
    step = required_query_string(:step, max_bytes: CoordinationLimits::MAX_KEY_BYTES)
    accepted = task.accepted_results[step]
    not_found!("Task result", task_id: task.id, step:) unless accepted

    render json: accepted
  end

  def claim
    task = lifecycle.claim!(task_id: params[:id], claim_id: required_string(:claim_id,
      max_bytes: CoordinationLimits::MAX_CLAIM_ID_BYTES),
      version: required_integer(:version))
    render json: { task: serialize_task(task) }
  end

  def takeover
    task = lifecycle.takeover!(task_id: params[:id], claim_id: required_string(:claim_id,
      max_bytes: CoordinationLimits::MAX_CLAIM_ID_BYTES),
      version: required_integer(:version), step: required_string(:step))
    render json: { task: serialize_task(task) }
  end

  def report
    task = lifecycle.report!(task_id: params[:id], claim_id: required_string(:claim_id,
      max_bytes: CoordinationLimits::MAX_CLAIM_ID_BYTES),
      version: required_integer(:version), step: required_string(:step), outcome: required_string(:outcome),
      result: required_text(:result, max_bytes: CoordinationLimits::MAX_RESULT_BYTES),
      message: optional_string(:message, max_bytes: CoordinationLimits::MAX_TEXT_BYTES))
    render json: { task: serialize_task(task) }
  end

  def answer
    task = lifecycle.answer!(task_id: params[:id], version: required_integer(:version),
      step: required_string(:step), answer: required_text(:answer, max_bytes: CoordinationLimits::MAX_TEXT_BYTES))
    render json: { task: serialize_task(task) }
  end

  private

  def required_query_string(name, max_bytes:)
    value = params.require(name)
    raise ActionController::BadRequest, "#{name} must be a bounded non-empty valid UTF-8 string" unless
      CoordinationLimits.valid_text?(value, max_bytes:)

    value
  end

  def lifecycle
    @lifecycle ||= TaskLifecycle.new
  end

  def serialize_task(task)
    task.as_json(only: %i[id task_plan_id workflow_id key title status current_step claim_id version pause_kind
      pause_message pause_step answer created_at updated_at]).merge(
        "workflow_key" => task.workflow.key,
        "workflow_revision" => task.workflow.revision,
        "blocker_ids" => task.blocker_ids.sort
      )
  end

  def find_task
    Task.includes(:workflow).find_by(id: params[:id]) || not_found!("Task", id: params[:id])
  end

  def pause_for(task)
    return unless task.pause_step

    { kind: task.pause_kind, step: task.pause_step, message: task.pause_message, answer: task.answer }
  end
end
