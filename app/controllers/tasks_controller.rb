class TasksController < ApplicationController
  def create
    task = lifecycle.create!(
      project: Project.find(required_integer(:project_id)),
      task_type: find_task_type,
      title: required_string(:title),
      description_markdown: required_string(:description_markdown),
      parent: find_optional_task(:parent_id),
      blockers: find_tasks(optional_integer_array(:blocker_ids, default: []))
    )

    render json: serialize(task), status: :created
  end

  def create_and_claim
    task = lifecycle.create_and_claim!(
      project: Project.find(required_integer(:project_id)),
      task_type: find_task_type,
      title: required_string(:title),
      description_markdown: required_string(:description_markdown),
      owner_id: required_string(:owner_id),
      creation_key: optional_string(:creation_key),
      parent: find_optional_task(:parent_id),
      blockers: find_tasks(optional_integer_array(:blocker_ids, default: []))
    )

    render json: serialize(task), status: :created
  end

  def show
    render json: serialize(lifecycle.show!(params[:id]))
  end

  def context
    task = Task.includes(:project, :workflow).find(params[:id])
    step = task.workflow.step_for(task.current_step)
    render json: {
      task: task.as_json(only: %i[id project_id title description_markdown status current_step owner_id claim_version
        lease_expires_at]),
      project: task.project.as_json(only: %i[id name repository_identity remote_url default_branch]),
      step: step.slice("id", "name", "instruction", "artifact_template", "model_tier").merge(
        "allowed_outcomes" => step.fetch("outcomes").keys),
      artifacts: artifact_index(task),
      pause: current_pause(task)
    }
  end

  def artifact
    task = Task.find(params[:id])
    accepted = task.accepted_artifacts[required_query_string(:step)]
    raise ActiveRecord::RecordNotFound unless accepted

    render json: accepted.slice("outcome", "markdown", "accepted_claim_version", "reconstructed")
  end

  def update
    attributes = { task_id: params[:id] }
    attributes[:description_markdown] = required_string(:description_markdown) if params.key?(:description_markdown)
    attributes[:parent] = find_optional_task(:parent_id) if params.key?(:parent_id)
    attributes[:blockers] = find_tasks(optional_integer_array(:blocker_ids)) if params.key?(:blocker_ids)
    raise ActionController::BadRequest, "no editable task fields were provided" if attributes.one?

    render json: serialize(lifecycle.update_definition!(**attributes))
  end

  def claim_next
    task_type = TaskType.find_by!(key: required_string(:task_type_key)) if params.key?(:task_type_key)
    task = lifecycle.claim_next!(
      project: Project.find(required_integer(:project_id)),
      owner_id: required_string(:owner_id),
      task_type:
    )
    return head :no_content unless task

    render json: serialize(task)
  end

  def claim
    render json: serialize(lifecycle.claim!(task_id: params[:id], owner_id: required_string(:owner_id)))
  end

  def show_owned
    task = lifecycle.show_owned(
      project: Project.find(required_query_integer(:project_id)),
      owner_id: required_string(:owner_id)
    )
    return head :no_content unless task

    render json: serialize(task)
  end

  def resumable
    tasks = lifecycle.resumable(
      project: Project.find(required_query_integer(:project_id)),
      task_type: TaskType.find_by!(key: required_string(:task_type_key))
    )
    render json: tasks.map { |task| serialize(task) }
  end

  def resume
    Task.find(params[:id])
    takeover_confirmed = params.fetch(:takeover_confirmed, false)
    unless takeover_confirmed == true || takeover_confirmed == false
      raise ActionController::BadRequest, "takeover_confirmed must be a boolean"
    end

    task = lifecycle.resume!(task_id: params[:id], owner_id: required_string(:owner_id),
      claim_version: required_integer(:claim_version), step: required_string(:step),
      answer: optional_string(:answer), takeover_confirmed:)
    render json: serialize(task)
  end

  def report_attempt
    task = lifecycle.report_attempt!(
      task_id: params[:id],
      owner_id: required_string(:owner_id),
      claim_version: required_integer(:claim_version),
      step: required_string(:step),
      outcome: required_string(:outcome),
      artifact: required_text(:artifact),
      message: optional_string(:message)
    )
    render json: serialize(task)
  end

  def cancel
    Task.find(params[:id])
    render json: serialize(lifecycle.cancel!(task_id: params[:id]))
  end

  def validate_children
    result = task_graph.validate!(parent: Task.find(params[:id]), children: required_children)
    render json: result
  end

  def materialize_children
    result = task_graph.materialize!(
      parent_id: params[:id],
      owner_id: required_string(:owner_id),
      claim_version: required_integer(:claim_version),
      expected_digest: required_string(:expected_digest),
      children: required_children
    )
    render json: { digest: result.fetch(:digest), children: result.fetch(:children).map { |task| serialize(task) } },
      status: :created
  end

  def children
    result = task_graph.observe(parent: Task.find(params[:id]))
    render json: {
      parent_id: result.fetch(:parent_id),
      digest: result.fetch(:digest),
      children: result.fetch(:children).map do |entry|
        serialize(entry.fetch(:task)).merge("sibling_blocker_ids" => entry.fetch(:sibling_blocker_ids))
      end
    }
  end

  private

  def required_query_string(name)
    value = params.require(name)
    raise ActionController::BadRequest, "#{name} must be a non-empty string" unless value.is_a?(String) && value.present?

    value
  end

  def artifact_index(task)
    task.accepted_artifacts.map do |step, artifact|
      artifact.slice("outcome", "accepted_claim_version", "reconstructed").merge("step" => step)
    end
  end

  def current_pause(task)
    return unless task.pause_step == task.current_step && task.pause_message.present?

    pause = { step: task.pause_step, claim_version: task.pause_claim_version, message: task.pause_message }
    if task.human_answer_step == task.pause_step && task.human_answer_claim_version == task.pause_claim_version
      pause[:answer] = task.human_answer
    end
    pause
  end

  def lifecycle
    @lifecycle ||= TaskLifecycle.new
  end

  def task_graph
    @task_graph ||= BriefTaskGraph.new
  end

  def required_children
    raise ActionController::ParameterMissing, :children unless params.key?(:children)

    value = params[:children]
    raise ActionController::BadRequest, "children must be an array" unless value.is_a?(Array)

    value.map { |child| child.respond_to?(:to_unsafe_h) ? child.to_unsafe_h : child }
  end

  def find_optional_task(name)
    id = optional_integer(name)
    Task.find(id) if id
  end

  def find_tasks(ids)
    return [] if ids.empty?

    Task.find(ids)
  end

  def find_task_type
    selectors = %i[task_type_key task_type_id].select { |name| params.key?(name) }
    raise ActionController::BadRequest, "provide exactly one task type selector" unless selectors.one?

    return TaskType.find_by!(key: required_string(:task_type_key)) if selectors.first == :task_type_key

    TaskType.find(required_integer(:task_type_id))
  end

  def serialize(task)
    task = Task.includes(:task_type, :workflow, :blockers).find(task.id)
    workflow = task.workflow
    step = workflow.step_for(task.current_step)

    {
      task: task.as_json(only: %i[id project_id task_type_id workflow_id parent_id title description_markdown status
        current_step owner_id claim_version lease_expires_at created_at updated_at]).merge(
          "task_type_key" => task.task_type.key, "blocker_ids" => task.blocker_ids.sort),
      workflow: workflow.as_json(only: %i[id name created_at]).merge("definition_json" => workflow.definition_for_execution),
      step:
    }
  end
end
