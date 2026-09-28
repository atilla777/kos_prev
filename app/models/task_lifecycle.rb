class TaskLifecycle
  class Error < StandardError; end
  class Conflict < Error; end
  class InvalidTransition < Error; end
  class InvalidInput < Error; end

  MAX_RESULT_BYTES = CoordinationLimits::MAX_RESULT_BYTES
  PAUSED_STATUSES = %w[needs_human blocked].freeze

  def ready(project:, task_plan: nil)
    incomplete = TaskDependency.where(blocker_id: Task.where.not(status: "completed")).select(:task_id)
    scope = Task.joins(:task_plan).where(task_plans: { project_id: project.id, status: "active" },
      status: "pending").where.not(id: incomplete)
    scope = scope.where(task_plan:) if task_plan
    scope.order(:created_at, :id)
  end

  def claim!(task_id:, claim_id:, version:)
    validate_claim_id!(claim_id)
    Task.transaction do
      task = lock_active_plan_for_task!(task_id)
      updated = ready(project: task.task_plan.project).where(id: task.id, version:).update_all(
        status: "active", claim_id:, version: Arel.sql("version + 1"), updated_at: Time.current
      )
      raise Conflict, "task is stale or not ready" unless updated == 1

      advance_plan!(task.task_plan_id)
      task.reload
    end
  end

  def takeover!(task_id:, claim_id:, version:, step:)
    validate_claim_id!(claim_id)
    update_fenced!(task_id:, scope: Task.where(status: "active", version:, current_step: step).where.not(claim_id:), changes: {
      claim_id:, version: Arel.sql("version + 1"), updated_at: Time.current
    }, message: "task is stale, not active at the reported step, or already has that claim")
  end

  def release!(task_id:, claim_id:, version:, step:)
    validate_claim_id!(claim_id)
    update_fenced!(task_id:, scope: Task.where(status: "active", claim_id:, version:, current_step: step), changes: {
      status: "pending", claim_id: nil, version: Arel.sql("version + 1"), updated_at: Time.current
    }, message: "task claim, version, or step is stale or task is not active")
  end

  def report!(task_id:, claim_id:, version:, step:, outcome:, result:, message: nil)
    validate_claim_id!(claim_id)
    validate_result!(result)

    Task.transaction do
      task = lock_active_plan_for_task!(task_id)
      fence = Task.where(id: task_id, status: "active", claim_id:, version:, current_step: step)
      raise Conflict, "task claim, version, or step is stale" unless fence.update_all("updated_at = updated_at") == 1

      task = Task.includes(:workflow).find(task_id)
      action = task.workflow.action_for(step, outcome)
      raise InvalidTransition, "outcome is not allowed for the reported step" unless action
      validate_pause_message!(message) if action["pause"]

      results = task.accepted_results.deep_dup
      results[step] = { "outcome" => outcome, "result" => result }
      if JSON.generate(results).bytesize > CoordinationLimits::MAX_ACCEPTED_RESULTS_BYTES
        raise InvalidInput, "accepted results must total at most 4 MiB"
      end
      changes = transition_changes(action, step:, message:).merge(
        accepted_results: results, version: Arel.sql("version + 1"), claim_id: nil, updated_at: Time.current
      )
      updated = fence.update_all(changes)
      raise Conflict, "task claim, version, or step is stale" unless updated == 1

      advance_plan!(task.task_plan_id)
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

  def abandon_plan!(task_plan:, version:)
    TaskPlan.transaction do
      fence = TaskPlan.where(id: task_plan.id, status: "active", version:)
      raise Conflict, "task plan is stale or already abandoned" unless fence.update_all("updated_at = updated_at") == 1

      unfinished = task_plan.tasks.where.not(status: "completed")
      started = unfinished.exists? && (unfinished.where.not(status: "pending").exists? ||
        unfinished.where.not(version: 0).exists? || unfinished.where.not(claim_id: nil).exists? ||
        task_plan.tasks.any? { |task| task.accepted_results.present? })
      raise Conflict, "task plan can be abandoned only after work has started" unless started

      unfinished.update_all(status: "abandoned", claim_id: nil, version: Arel.sql("version + 1"), updated_at: Time.current)
      updated = fence.update_all(status: "abandoned", version: Arel.sql("version + 1"), updated_at: Time.current)
      raise Conflict, "task plan is stale or already abandoned" unless updated == 1

      task_plan.reload
    end
  end

  private

  def update_fenced!(task_id:, scope:, changes:, message:)
    Task.transaction do
      task = lock_active_plan_for_task!(task_id)
      updated = scope.where(id: task_id).update_all(changes)
      raise Conflict, message unless updated == 1

      advance_plan!(task.task_plan_id)
      Task.find(task_id)
    end
  end

  def lock_active_plan_for_task!(task_id)
    task = Task.includes(task_plan: :project).find(task_id)
    updated = TaskPlan.where(id: task.task_plan_id, status: "active").update_all("updated_at = updated_at")
    raise Conflict, "task plan is abandoned" unless updated == 1

    task
  end

  def advance_plan!(task_plan_id)
    updated = TaskPlan.where(id: task_plan_id, status: "active").update_all(
      version: Arel.sql("version + 1"), updated_at: Time.current
    )
    raise Conflict, "task plan is abandoned" unless updated == 1
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
    valid = CoordinationLimits.valid_text?(claim_id, max_bytes: CoordinationLimits::MAX_CLAIM_ID_BYTES)
    raise InvalidInput, "claim_id must be a nonblank valid UTF-8 string of at most 200 bytes" unless valid
  end

  def validate_result!(result)
    valid = result.is_a?(String) && !result.empty? && result.encoding == Encoding::UTF_8 && result.valid_encoding?
    raise InvalidInput, "result must be a nonempty valid UTF-8 string" unless valid
    raise InvalidInput, "result must be at most 1 MiB" if result.bytesize > MAX_RESULT_BYTES
  end

  def validate_pause_message!(message)
    valid = CoordinationLimits.valid_text?(message, max_bytes: CoordinationLimits::MAX_TEXT_BYTES)
    raise InvalidInput, "message must be a nonblank valid UTF-8 string of at most 16 KiB for a pause" unless valid
  end

  def validate_answer!(answer)
    valid = CoordinationLimits.valid_text?(answer, max_bytes: CoordinationLimits::MAX_TEXT_BYTES)
    raise InvalidInput, "answer must be a nonblank valid UTF-8 string of at most 16 KiB" unless valid
  end
end
