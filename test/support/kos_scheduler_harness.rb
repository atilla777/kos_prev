require "time"

class KosSchedulerHarness
  Result = Data.define(:reason, :state)

  def initialize(cli:, main_runner:, subagent_runner:, clock: -> { Time.now.utc })
    @cli = cli
    @main_runner = main_runner
    @subagent_runner = subagent_runner
    @clock = clock
  end

  def run(task_id:, owner_id:)
    state = @cli.show(task_id)
    recovered = false

    loop do
      task = state.fetch("task")
      status = task.fetch("status")
      return Result.new(reason: status, state:) if %w[completed cancelled needs_human blocked].include?(status)
      return Result.new(reason: "invalid_state", state:) unless status == "active"

      if lease_expired?(task)
        return Result.new(reason: "recovery_exhausted", state:) if recovered

        begin
          @cli.resume(task_id:, owner_id:, claim_version: task.fetch("claim_version"),
            step: task.fetch("current_step"))
        rescue StandardError
          return Result.new(reason: "resume_failed", state:)
        end
        resumed = @cli.show(task_id)
        resumed_status = resumed.fetch("task").fetch("status")
        return Result.new(reason: resumed_status, state: resumed) if terminal?(resumed_status)
        unless resume_confirmed?(task, resumed, owner_id)
          return Result.new(reason: "resume_unconfirmed", state: resumed)
        end

        recovered = true
        state = resumed
        next
      end

      before = state
      return Result.new(reason: "invalid_state", state:) unless dispatch(task_id, state)

      state = @cli.show(task_id)
      next if progress?(before, state)
      next if lease_expired?(state.fetch("task")) && !recovered

      return Result.new(reason: "unchanged", state:)
    end
  rescue KeyError, ArgumentError
    Result.new(reason: "invalid_state", state: state)
  end

  def run_custom(project_id:, task_type_key:, owner_id:, answer: nil)
    raise ArgumentError, "task type key must be nonblank" if task_type_key.blank?
    raise ArgumentError, "reserved task type key" if %w[brief development fix].include?(task_type_key)

    selected = @cli.resumable(project_id:, task_type_key:).first
    selected ||= @cli.claim_next(project_id:, task_type_key:, owner_id:)
    return Result.new(reason: "unavailable", state: nil) unless selected

    task = selected.fetch("task")
    if task.fetch("status") == "needs_human" && answer
      @cli.resume(task_id: task.fetch("id"), owner_id:, claim_version: task.fetch("claim_version"),
        step: task.fetch("current_step"), answer:)
    end
    run(task_id: task.fetch("id"), owner_id:)
  end

  private

  def dispatch(task_id, state)
    step = state.fetch("step")

    case step.fetch("execution_mode")
    when "main"
      @main_runner.call(task_id)
    when "subagent"
      @subagent_runner.call(tier: step.fetch("model_tier"), prompt: task_id.to_s)
    else
      return false
    end
    true
  rescue StandardError
    true
  end

  def progress?(before, after)
    before_task = before.fetch("task")
    after_task = after.fetch("task")
    fields = %w[status current_step claim_version]

    fields.any? { |field| before_task.fetch(field) != after_task.fetch(field) } ||
      current_step_evidence(before) != current_step_evidence(after, before_task.fetch("current_step"))
  end

  def resume_confirmed?(before_task, after, owner_id)
    after_task = after.fetch("task")
    after_task.fetch("status") == "active" &&
      after_task.fetch("owner_id") == owner_id &&
      after_task.fetch("current_step") == before_task.fetch("current_step") &&
      after_task.fetch("claim_version") == before_task.fetch("claim_version") + 1 &&
      !lease_expired?(after_task)
  end

  def terminal?(status)
    %w[completed cancelled needs_human blocked].include?(status)
  end

  def current_step_evidence(state, step = state.fetch("task").fetch("current_step"))
    state.fetch("artifacts").find { |artifact| artifact.fetch("step") == step }
  end

  def lease_expired?(task)
    Time.iso8601(task.fetch("lease_expires_at")) <= @clock.call
  end
end
