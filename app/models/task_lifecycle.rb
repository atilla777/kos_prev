class TaskLifecycle
  class Error < StandardError; end
  class Conflict < Error; end
  class InvalidTransition < Error; end
  class InvalidInput < Error; end

  MAX_RESULT_BYTES = 1.megabyte
  PAUSED_STATUSES = %w[needs_human blocked].freeze

  def ready(project:, task_plan: nil)
    incomplete = TaskDependency.where(blocker_id: Task.where.not(status: "completed")).select(:task_id)
    scope = Task.joins(:task_plan).where(task_plans: { project_id: project.id }, status: "pending").where.not(id: incomplete)
    scope = scope.where(task_plan:) if task_plan
    scope.order(:created_at, :id)
  end

  def claim!(task_id:, claim_id:, version:)
    validate_claim_id!(claim_id)
    task = Task.find(task_id)

    Task.transaction do
      updated = ready(project: task.task_plan.project).where(id: task.id, version:).update_all(
        status: "active", claim_id:, version: Arel.sql("version + 1"), updated_at: Time.current
      )
      raise Conflict, "task is stale or not ready" unless updated == 1

      task.reload
    end
  end

  def takeover!(task_id:, claim_id:, version:, step:)
    validate_claim_id!(claim_id)
    update_fenced!(task_id:, scope: Task.where(status: "active", version:, current_step: step).where.not(claim_id:), changes: {
      claim_id:, version: Arel.sql("version + 1"), updated_at: Time.current
    }, message: "task is stale, not active at the reported step, or already has that claim")
  end

  def report!(task_id:, claim_id:, version:, step:, outcome:, result:, message: nil)
    validate_claim_id!(claim_id)
    validate_result!(result)

    Task.transaction do
      fence = Task.where(id: task_id, status: "active", claim_id:, version:, current_step: step)
      raise Conflict, "task claim, version, or step is stale" unless fence.update_all("updated_at = updated_at") == 1

      task = Task.includes(:workflow).find(task_id)
      action = task.workflow.action_for(step, outcome)
      raise InvalidTransition, "outcome is not allowed for the reported step" unless action
      validate_pause_message!(message) if action["pause"]

      results = task.accepted_results.deep_dup
      results[step] = { "outcome" => outcome, "result" => result }
      changes = transition_changes(action, step:, message:).merge(
        accepted_results: results, version: Arel.sql("version + 1"), claim_id: nil, updated_at: Time.current
      )
      updated = fence.update_all(changes)
      raise Conflict, "task claim, version, or step is stale" unless updated == 1

      task.reload
    end
  end

  def answer!(task_id:, version:, step:, answer:)
    validate_answer!(answer)
    update_fenced!(task_id:, scope: Task.where(status: PAUSED_STATUSES, version:, current_step: step, pause_step: step),
      changes: {
        status: "pending", claim_id: nil, answer:, version: Arel.sql("version + 1"), updated_at: Time.current
      }, message: "task pause, version, or step is stale")
  end

  private

  def update_fenced!(task_id:, scope:, changes:, message:)
    Task.transaction do
      Task.find(task_id)
      updated = scope.where(id: task_id).update_all(changes)
      raise Conflict, message unless updated == 1

      Task.find(task_id)
    end
  end

  def transition_changes(action, step:, message:)
    cleared = { pause_kind: nil, pause_message: nil, pause_step: nil, answer: nil }
    if action.key?("next_step")
      cleared.merge(status: "pending", current_step: action.fetch("next_step"))
    elsif action.key?("pause")
      { status: action.fetch("pause"), pause_kind: action.fetch("pause"), pause_message: message, pause_step: step,
        answer: nil }
    elsif action["complete_task"] == true
      cleared.merge(status: "completed")
    else
      raise InvalidTransition, "workflow outcome has no supported action"
    end
  end

  def validate_claim_id!(claim_id)
    raise InvalidInput, "claim_id must be a nonblank string" unless claim_id.is_a?(String) && claim_id.present?
  end

  def validate_result!(result)
    valid = result.is_a?(String) && !result.empty? && result.encoding == Encoding::UTF_8 && result.valid_encoding?
    raise InvalidInput, "result must be a nonempty valid UTF-8 string" unless valid
    raise InvalidInput, "result must be at most 1 MiB" if result.bytesize > MAX_RESULT_BYTES
  end

  def validate_pause_message!(message)
    raise InvalidInput, "message must be a nonblank string for a pause" unless message.is_a?(String) && message.present?
  end

  def validate_answer!(answer)
    valid = answer.is_a?(String) && answer.present? && answer.encoding == Encoding::UTF_8 && answer.valid_encoding?
    raise InvalidInput, "answer must be a nonblank valid UTF-8 string" unless valid
  end
end
