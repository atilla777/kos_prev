require "time"

class KosSchedulerHarness
  Result = Data.define(:reason, :context)

  def initialize(cli:, main_runner:, subagent_runner:, clock: -> { Time.now.utc })
    @cli = cli
    @main_runner = main_runner
    @subagent_runner = subagent_runner
    @clock = clock
  end

  def run(task_id:, owner_id:)
    context = @cli.context(task_id)
    recovered = false

    loop do
      task = context.fetch("task")
      status = task.fetch("status")
      return Result.new(reason: status, context:) if %w[completed cancelled needs_human blocked].include?(status)
      return Result.new(reason: "invalid_context", context:) unless status == "active"

      if lease_expired?(task)
        return Result.new(reason: "recovery_exhausted", context:) if recovered

        begin
          @cli.resume(task_id:, owner_id:, claim_version: task.fetch("claim_version"),
            step: task.fetch("current_step"))
        rescue StandardError
          return Result.new(reason: "resume_failed", context:)
        end
        resumed = @cli.context(task_id)
        resumed_status = resumed.fetch("task").fetch("status")
        return Result.new(reason: resumed_status, context: resumed) if terminal?(resumed_status)
        unless resume_confirmed?(task, resumed, owner_id)
          return Result.new(reason: "resume_unconfirmed", context: resumed)
        end

        recovered = true
        context = resumed
        next
      end

      before = context
      return Result.new(reason: "invalid_context", context:) unless dispatch(task_id, context)

      context = @cli.context(task_id)
      next if progress?(before, context)
      next if lease_expired?(context.fetch("task")) && !recovered

      return Result.new(reason: "unchanged", context:)
    end
  rescue KeyError, ArgumentError
    Result.new(reason: "invalid_context", context: context)
  end

  def run_custom(project_id:, task_type_key:, owner_id:, answer: nil)
    raise ArgumentError, "task type key must be nonblank" if task_type_key.blank?
    raise ArgumentError, "reserved task type key" if %w[brief development fix].include?(task_type_key)

    selected = @cli.resumable(project_id:, task_type_key:).first
    selected ||= @cli.claim_next(project_id:, task_type_key:, owner_id:)
    return Result.new(reason: "unavailable", context: nil) unless selected

    task = selected.fetch("task")
    if task.fetch("status") == "needs_human" && answer
      @cli.resume(task_id: task.fetch("id"), owner_id:, claim_version: task.fetch("claim_version"),
        step: task.fetch("current_step"), answer:)
    end
    run(task_id: task.fetch("id"), owner_id:)
  end

  private

  def dispatch(task_id, context)
    step = context.fetch("step")

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

  def current_step_evidence(context, step = context.fetch("task").fetch("current_step"))
    context.fetch("artifacts").find { |artifact| artifact.fetch("step") == step }
  end

  def lease_expired?(task)
    Time.iso8601(task.fetch("lease_expires_at")) <= @clock.call
  end
end
