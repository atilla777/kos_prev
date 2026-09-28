require "test_helper"

class TaskLifecycleTest < ActiveSupport::TestCase
  setup do
    @project = create_project
    @workflow = create_workflow(key: "delivery")
    @store = TaskPlanStore.new
    @lifecycle = TaskLifecycle.new
  end

  test "stores and replaces a complete unstarted plan atomically" do
    plan = @store.replace!(project: @project, key: "release", title: "Release", task_definitions: [
      plan_task(key: "first", workflow: @workflow),
      plan_task(key: "second", workflow: @workflow, blockers: [ "first" ])
    ])
    assert_equal %w[first second], plan.tasks.order(:id).pluck(:key)
    assert_equal [ "first" ], plan.tasks.find_by!(key: "second").blockers.pluck(:key)

    replacement = @store.replace!(project: @project, key: "release", title: "Smaller", task_definitions: [
      plan_task(key: "only", workflow: @workflow)
    ])
    assert_equal plan.id, replacement.id
    assert_equal 1, replacement.version
    assert_equal [ "only" ], replacement.tasks.pluck(:key)
  end

  test "tasks stay pinned to the workflow revision resolved when the plan is stored" do
    plan = @store.replace!(project: @project, key: "release", title: "Release",
      task_definitions: [ plan_task(key: "work", workflow: @workflow) ])
    original_task = plan.tasks.first
    replacement_workflow = create_workflow(key: @workflow.key, revision: 2)

    assert_equal @workflow.id, original_task.reload.workflow_id

    plan = @store.replace!(project: @project, key: "release", title: "Revised",
      task_definitions: [ plan_task(key: "work", workflow: replacement_workflow) ])
    assert_equal replacement_workflow.id, plan.tasks.first.workflow_id
  end

  test "invalid or started replacement leaves the whole plan unchanged" do
    plan = @store.replace!(project: @project, key: "release", title: "Release", task_definitions: [
      plan_task(key: "first", workflow: @workflow)
    ])
    before = plan.tasks.pluck(:id, :key)

    assert_raises(TaskPlanStore::InvalidDefinition) do
      @store.replace!(project: @project, key: "release", title: "Invalid", task_definitions: [
        plan_task(key: "a", workflow: @workflow, blockers: [ "b" ]),
        plan_task(key: "b", workflow: @workflow, blockers: [ "a" ])
      ])
    end
    assert_equal before, plan.reload.tasks.pluck(:id, :key)

    task = plan.tasks.first
    @lifecycle.claim!(task_id: task.id, claim_id: "worker", version: 0)
    assert_raises(TaskLifecycle::Conflict) do
      @store.replace!(project: @project, key: "release", title: "Too late",
        task_definitions: [ plan_task(key: "new", workflow: @workflow) ])
    end
    assert_equal [ "first" ], plan.reload.tasks.pluck(:key)
  end

  test "only dependency-ready pending tasks are claimable" do
    plan = @store.replace!(project: @project, key: "release", title: "Release", task_definitions: [
      plan_task(key: "first", workflow: @workflow),
      plan_task(key: "independent", workflow: @workflow),
      plan_task(key: "last", workflow: @workflow, blockers: [ "first" ])
    ])
    assert_equal %w[first independent], @lifecycle.ready(project: @project).pluck(:key).sort

    blocked = plan.tasks.find_by!(key: "last")
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.claim!(task_id: blocked.id, claim_id: "worker", version: 0)
    end
  end

  test "dependencies cannot cross task plan boundaries" do
    task = create_task(project: @project, workflow: @workflow)
    blocker = create_task(project: @project, workflow: @workflow)

    dependency = TaskDependency.new(task:, blocker:)
    assert_not dependency.valid?
    assert_includes dependency.errors[:blocker], "must belong to the same task plan as the task"
  end

  test "claim and takeover use exact optimistic fences" do
    task = create_task(project: @project, workflow: @workflow)
    claimed = @lifecycle.claim!(task_id: task.id, claim_id: "first", version: 0)
    assert_equal [ "active", "first", 1 ], claimed.values_at(:status, :claim_id, :version)
    assert_equal 1, task.task_plan.reload.version
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.claim!(task_id: task.id, claim_id: "second", version: 0)
    end
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.takeover!(task_id: task.id, claim_id: "first", version: 1, step: "work")
    end

    taken = @lifecycle.takeover!(task_id: task.id, claim_id: "second", version: 1, step: "work")
    assert_equal [ "second", 2 ], taken.values_at(:claim_id, :version)
    assert_equal 2, task.task_plan.reload.version
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.takeover!(task_id: task.id, claim_id: "third", version: 1, step: "work")
    end
  end

  test "reports store the latest result and release each step claim" do
    task = create_task(project: @project, workflow: @workflow)
    task = @lifecycle.claim!(task_id: task.id, claim_id: "worker", version: 0)
    task = @lifecycle.report!(task_id: task.id, claim_id: "worker", version: 1, step: "work", outcome: "done",
      result: "Implemented")

    assert_equal [ "pending", "review", nil, 2 ], task.values_at(:status, :current_step, :claim_id, :version)
    assert_equal({ "outcome" => "done", "result" => "Implemented" }, task.accepted_results.fetch("work"))
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.report!(task_id: task.id, claim_id: "worker", version: 1, step: "work", outcome: "done",
        result: "Duplicate")
    end
    assert_equal "Implemented", task.reload.accepted_results.dig("work", "result")

    task = @lifecycle.claim!(task_id: task.id, claim_id: "reviewer", version: 2)
    task = @lifecycle.report!(task_id: task.id, claim_id: "reviewer", version: 3, step: "review",
      outcome: "changes_requested", result: "Fix this")
    task = @lifecycle.claim!(task_id: task.id, claim_id: "worker-2", version: 4)
    task = @lifecycle.report!(task_id: task.id, claim_id: "worker-2", version: 5, step: "work", outcome: "done",
      result: "Reimplemented")
    assert_equal "Reimplemented", task.accepted_results.dig("work", "result")
  end

  test "pause and answer remain bound to the same step" do
    task = create_task(project: @project, workflow: @workflow)
    task = @lifecycle.claim!(task_id: task.id, claim_id: "worker", version: 0)
    task = @lifecycle.report!(task_id: task.id, claim_id: "worker", version: 1, step: "work", outcome: "question",
      result: "Need a choice", message: "Which option?")
    assert_equal [ "needs_human", "needs_human", "work", nil, 2 ],
      task.values_at(:status, :pause_kind, :pause_step, :claim_id, :version)

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.answer!(task_id: task.id, version: 1, step: "work", answer: "A")
    end
    task = @lifecycle.answer!(task_id: task.id, version: 2, step: "work", answer: "A")
    assert_equal [ "pending", "work", "A", 3 ], task.values_at(:status, :current_step, :answer, :version)
  end

  test "generic completion has no built-in special case" do
    definition = { "steps" => [ {
      "id" => "finish", "name" => "Finish", "instruction" => "Finish now.",
      "outcomes" => { "done" => { "complete_task" => true } }
    } ] }
    workflow = create_workflow(key: "custom", definition:)
    task = create_task(project: @project, workflow:)
    task = @lifecycle.claim!(task_id: task.id, claim_id: "worker", version: 0)
    task = @lifecycle.report!(task_id: task.id, claim_id: "worker", version: 1, step: "finish", outcome: "done",
      result: "Finished")
    assert_equal "completed", task.status
  end


  test "abandons every unfinished task atomically and preserves inspection state" do
    plan = create_task_plan(project: @project)
    completed = create_task(task_plan: plan, workflow: @workflow, key: "completed")
    completed.update!(status: "completed", version: 4,
      accepted_results: { "work" => { "outcome" => "done", "result" => "kept" } })
    active = create_task(task_plan: plan, workflow: @workflow, key: "active")
    active.update!(status: "active", claim_id: "worker", version: 2,
      accepted_results: { "work" => { "outcome" => "done", "result" => "partial" } })
    paused = create_task(task_plan: plan, workflow: @workflow, key: "paused")
    paused.update!(status: "needs_human", pause_kind: "needs_human", pause_message: "Choose",
      pause_step: "work", answer: "A", version: 3)
    pending = create_task(task_plan: plan, workflow: @workflow, key: "pending")
    TaskDependency.create!(task: pending, blocker: active)

    abandoned = @lifecycle.abandon_plan!(task_plan: plan, version: 0)

    assert_equal [ "abandoned", 1 ], abandoned.values_at(:status, :version)
    assert_equal [ "completed", 4, "kept" ], completed.reload.values_at(:status, :version).push(
      completed.accepted_results.dig("work", "result"))
    assert_equal [ "abandoned", nil, 3, "partial" ], active.reload.values_at(:status, :claim_id, :version).push(
      active.accepted_results.dig("work", "result"))
    assert_equal [ "abandoned", "Choose", "A", 4 ],
      paused.reload.values_at(:status, :pause_message, :answer, :version)
    assert_equal [ "abandoned", 1 ], pending.reload.values_at(:status, :version)
    assert_empty @lifecycle.ready(project: @project)

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.report!(task_id: active.id, claim_id: "worker", version: 2, step: "work", outcome: "done",
        result: "stale")
    end
    assert_raises(TaskLifecycle::Conflict) { @lifecycle.abandon_plan!(task_plan: plan, version: 0) }
    assert_raises(TaskLifecycle::Conflict) do
      @store.replace!(project: @project, key: plan.key, title: "Replacement",
        task_definitions: [ plan_task(key: "new", workflow: @workflow) ])
    end
  end

  test "rejects unstarted or stale abandonment without changing the plan" do
    plan = create_task_plan(project: @project)
    task = create_task(task_plan: plan, workflow: @workflow)

    assert_raises(TaskLifecycle::Conflict) { @lifecycle.abandon_plan!(task_plan: plan, version: 0) }
    task.update!(status: "active", claim_id: "worker")
    plan.update!(version: 2)
    assert_raises(TaskLifecycle::Conflict) { @lifecycle.abandon_plan!(task_plan: plan, version: 1) }

    assert_equal [ "active", 2 ], plan.reload.values_at(:status, :version)
    assert_equal [ "active", "worker", 0 ], task.reload.values_at(:status, :claim_id, :version)
  end
end

class TaskLifecycleConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    TaskDependency.delete_all
    Task.delete_all
    TaskPlan.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  teardown do
    TaskDependency.delete_all
    Task.delete_all
    TaskPlan.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  test "independent tasks can be claimed while conflicting exact claims have one winner" do
    project = create_project
    workflow = create_workflow
    first = create_task(project:, workflow:)
    second = create_task(project:, workflow:)

    independent = [ [ first, "first" ], [ second, "second" ] ].map do |task, claim_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          TaskLifecycle.new.claim!(task_id: task.id, claim_id:, version: 0)
        end
      end
    end.map(&:value)
    assert_equal %w[first second], independent.map(&:claim_id).sort

    exact = create_task(project:, workflow:)
    gate = Queue.new
    outcomes = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          TaskLifecycle.new.claim!(task_id: exact.id, claim_id: "worker-#{index}", version: 0)
        rescue StandardError => error
          error
        end
      end
    end
    2.times { gate << true }
    results = outcomes.map(&:value)
    assert_equal 1, results.grep(Task).size
    assert_equal 1, results.grep(TaskLifecycle::Conflict).size
  end

  test "concurrent reports for one claim and version have one winner" do
    project = create_project
    workflow = create_workflow
    task = create_task(project:, workflow:)
    TaskLifecycle.new.claim!(task_id: task.id, claim_id: "worker", version: 0)
    gate = Queue.new

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          TaskLifecycle.new.report!(task_id: task.id, claim_id: "worker", version: 1, step: "work", outcome: "done",
            result: "Result #{index}")
        rescue StandardError => error
          error
        end
      end
    end
    2.times { gate << true }
    results = threads.map(&:value)

    assert_equal 1, results.grep(Task).size
    assert_equal 1, results.grep(TaskLifecycle::Conflict).size
    assert_includes [ "Result 0", "Result 1" ], task.reload.accepted_results.dig("work", "result")
  end


  test "abandonment races atomically with every task lifecycle mutation" do
    {
      claim: ->(lifecycle, task) { lifecycle.claim!(task_id: task.id, claim_id: "new", version: task.version) },
      report: ->(lifecycle, task) do
        lifecycle.report!(task_id: task.id, claim_id: task.claim_id, version: task.version, step: "work",
          outcome: "done", result: "finished")
      end,
      answer: ->(lifecycle, task) do
        lifecycle.answer!(task_id: task.id, version: task.version, step: "work", answer: "A")
      end,
      takeover: ->(lifecycle, task) do
        lifecycle.takeover!(task_id: task.id, claim_id: "new", version: task.version, step: "work")
      end
    }.each do |operation, mutation|
      plan, task = abandonment_race_state(operation)
      observed_plan_version = plan.version
      gate = Queue.new
      threads = [
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            gate.pop
            mutation.call(TaskLifecycle.new, task)
          rescue StandardError => error
            error
          end
        end,
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            gate.pop
            TaskLifecycle.new.abandon_plan!(task_plan: TaskPlan.find(plan.id), version: observed_plan_version)
          rescue StandardError => error
            error
          end
        end
      ]
      2.times { gate << true }
      results = threads.map(&:value)

      assert_equal 1, results.count { |result| result.is_a?(Task) || result.is_a?(TaskPlan) }, operation
      assert_equal 1, results.grep(TaskLifecycle::Conflict).size, operation
      if plan.reload.status == "abandoned"
        assert_equal "abandoned", task.reload.status, operation
        assert_nil task.claim_id, operation
      else
        assert_equal observed_plan_version + 1, plan.version, operation
        assert_empty plan.tasks.where(status: "abandoned"), operation
      end
    end
  end

  private

  def abandonment_race_state(operation)
    project = create_project(name: operation.to_s)
    workflow = create_workflow
    plan = create_task_plan(project:)
    completed = create_task(task_plan: plan, workflow:, key: "completed")
    completed.update!(status: "completed", accepted_results: {
      "work" => { "outcome" => "done", "result" => "kept" }
    })
    task = create_task(task_plan: plan, workflow:, key: "target")
    case operation
    when :report, :takeover
      task.update!(status: "active", claim_id: "worker", version: 1)
    when :answer
      task.update!(status: "needs_human", pause_kind: "needs_human", pause_message: "Choose", pause_step: "work",
        version: 1)
    end
    [ plan.reload, task.reload ]
  end
end
