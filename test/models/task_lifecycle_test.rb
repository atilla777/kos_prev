require "test_helper"
require "timeout"

class TaskLifecycleTest < ActiveSupport::TestCase
  setup do
    @now = Time.zone.local(2026, 9, 19, 12)
    @lifecycle = TaskLifecycle.new(clock: -> { @now }, lease_duration: 2.hours)
  end

  test "creates a task with the task type workflow and its first step" do
    project = create_project
    original_workflow = create_workflow
    task_type = create_task_type(workflow: original_workflow)

    task = @lifecycle.create!(project:, task_type:, title: "Lifecycle", description_markdown: "Description")

    assert_equal original_workflow, task.workflow
    assert_equal "develop", task.current_step
    assert_equal "pending", task.status
    assert_equal 0, task.claim_version
  end

  test "creates blockers atomically" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    blocker = create_task(project:, workflow:, task_type:)

    task = @lifecycle.create!(project:, task_type:, title: "Blocked", description_markdown: "Description",
      blockers: [ blocker ])

    assert_equal [ blocker ], task.blockers
  end

  test "rolls task creation back when a blocker is invalid" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    other_project_blocker = create_task

    assert_no_difference -> { project.tasks.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        @lifecycle.create!(project:, task_type:, title: "Invalid", description_markdown: "Description",
          blockers: [ other_project_blocker ])
      end
    end
  end

  test "create and claim rolls back when a blocker is incomplete" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    blocker = create_task(project:, workflow:, task_type:)

    assert_no_difference -> { project.tasks.count } do
      assert_raises(TaskLifecycle::Conflict) do
        @lifecycle.create_and_claim!(project:, task_type:, title: "Blocked", description_markdown: "Description",
          owner_id: "session", blockers: [ blocker ])
      end
    end
  end

  test "snapshots the task type workflow at creation" do
    project = create_project
    original_workflow = create_workflow(name: "Original")
    replacement_workflow = create_workflow(name: "Replacement")
    task_type = create_task_type(workflow: original_workflow)

    first = @lifecycle.create!(project:, task_type:, title: "First", description_markdown: "Description")
    task_type.update!(workflow: replacement_workflow)
    second = @lifecycle.create!(project:, task_type:, title: "Second", description_markdown: "Description")

    assert_equal original_workflow, first.reload.workflow
    assert_equal replacement_workflow, second.workflow
  end

  test "show reads without changing ownership" do
    task = create_task

    shown = @lifecycle.show!(task.id)

    assert_equal task, shown
    assert_equal 0, shown.claim_version
    assert_nil shown.owner_id
  end

  test "claim next chooses the oldest available task and records a fenced lease" do
    project = create_project
    blocker = create_task(project:, title: "Blocker")
    @lifecycle.cancel!(task_id: blocker.id)
    blocked = create_task(project:, title: "Blocked")
    TaskDependency.create!(task: blocked, blocker:)
    available = create_task(project:, title: "Available")

    claimed = @lifecycle.claim_next!(project:, owner_id: "session-1")

    assert_equal available, claimed
    assert_equal "active", claimed.status
    assert_equal "session-1", claimed.owner_id
    assert_equal 1, claimed.claim_version
    assert_equal @now + 2.hours, claimed.lease_expires_at
    assert_nil @lifecycle.claim_next!(project:, owner_id: "session-2")
  end

  test "claim next filters by task type" do
    project = create_project
    workflow = create_workflow
    other_type = create_task_type(name: "Other", workflow:)
    requested_type = create_task_type(name: "Requested", workflow:)
    create_task(project:, workflow:, task_type: other_type, title: "Older")
    requested = create_task(project:, workflow:, task_type: requested_type, title: "Requested")

    claimed = @lifecycle.claim_next!(project:, task_type: requested_type, owner_id: "session")

    assert_equal requested, claimed
    assert_equal "pending", project.tasks.find_by(title: "Older").status
  end

  test "claims an exact available task and rejects incomplete blockers" do
    project = create_project
    blocker = create_task(project:, title: "Blocker")
    blocked = create_task(project:, title: "Blocked")
    TaskDependency.create!(task: blocked, blocker:)

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.claim!(task_id: blocked.id, owner_id: "session")
    end
    assert_equal blocker, @lifecycle.claim!(task_id: blocker.id, owner_id: "session")
  end

  test "create and claim is idempotent for an exact definition" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    blocker = create_task(project:, workflow:, task_type:)
    blocker = @lifecycle.claim!(task_id: blocker.id, owner_id: "blocker-session")
    blocker = @lifecycle.report_attempt!(task_id: blocker.id, owner_id: "blocker-session",
      claim_version: blocker.claim_version, step: "develop", outcome: "ready", artifact: "# Develop")
    blocker = @lifecycle.report_attempt!(task_id: blocker.id, owner_id: "blocker-session",
      claim_version: blocker.claim_version, step: "check", outcome: "passed", artifact: "# Check")
    arguments = {
      project:, task_type:, title: "Created", description_markdown: "Description", owner_id: "session",
      blockers: [ blocker ]
    }

    first = @lifecycle.create_and_claim!(**arguments)
    repeated = @lifecycle.create_and_claim!(**arguments)

    assert_equal first, repeated
    assert_equal 2, project.tasks.count
    assert_equal "active", first.status
    assert_equal 1, first.claim_version
    assert_equal @now + 2.hours, first.lease_expires_at
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.create_and_claim!(**arguments.merge(title: "Different"))
    end
  end

  test "creation key returns the exact task without changing progressed paused or completed lifecycle state" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)

    %w[progressed blocked completed].each do |final_state|
      owner = "initial-#{final_state}"
      arguments = {
        project:, task_type:, title: final_state, description_markdown: "Description", owner_id: owner,
        creation_key: "request:fix:sha256:#{final_state}"
      }
      task = @lifecycle.create_and_claim!(**arguments)
      task = @lifecycle.report_attempt!(task_id: task.id, owner_id: owner, claim_version: task.claim_version,
        step: "develop", outcome: "ready", artifact: "# Develop")
      if final_state != "progressed"
        outcome = final_state == "blocked" ? "blocked" : "passed"
        task = @lifecycle.report_attempt!(task_id: task.id, owner_id: owner, claim_version: task.claim_version,
          step: "check", outcome:, artifact: "# Check", message: ("Infrastructure unavailable" if outcome == "blocked"))
      end
      before = task.attributes

      repeated = @lifecycle.create_and_claim!(**arguments.merge(owner_id: "retry-#{final_state}"))

      assert_equal task.id, repeated.id
      assert_equal before, repeated.attributes
    end
    assert_equal 3, Task.where(project:, task_type:).count
  end

  test "creation key rejects a different immutable definition and unsafe keys" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    arguments = {
      project:, task_type:, title: "Created", description_markdown: "Description", owner_id: "session",
      creation_key: "request:fix:sha256:abc"
    }
    @lifecycle.create_and_claim!(**arguments)

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.create_and_claim!(**arguments.merge(owner_id: "other", description_markdown: "Different"))
    end
    [ "", " leading", "unsafe/key", "a" * 201 ].each do |creation_key|
      assert_raises(TaskLifecycle::InvalidInput) do
        @lifecycle.create_and_claim!(**arguments.merge(owner_id: SecureRandom.hex, creation_key:))
      end
    end
    assert_equal 1, Task.where(project:, task_type:).count
  end

  test "one owner cannot claim two tasks" do
    project = create_project
    first = create_task(project:, title: "First")
    second = create_task(project:, title: "Second")

    assert_equal first, @lifecycle.claim!(task_id: first.id, owner_id: "session")
    assert_raises(TaskLifecycle::Conflict) { @lifecycle.claim!(task_id: second.id, owner_id: "session") }
    assert_equal "pending", second.reload.status
  end

  test "owned and resumable queries do not change lifecycle state" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    active = create_task(project:, workflow:, task_type:, title: "Active")
    paused = create_task(project:, workflow:, task_type:, title: "Paused")
    active = @lifecycle.claim!(task_id: active.id, owner_id: "session")
    paused = @lifecycle.claim!(task_id: paused.id, owner_id: "pause-session")
    paused = @lifecycle.report_attempt!(task_id: paused.id, owner_id: "pause-session",
      claim_version: paused.claim_version, step: "develop", outcome: "question", artifact: "# Question",
      message: "Which behavior?")

    assert_equal active, @lifecycle.show_owned(project:, owner_id: "session")
    assert_equal [ active, paused ], @lifecycle.resumable(project:, task_type:).to_a
    assert_equal 1, active.reload.claim_version
    assert_equal 2, paused.reload.claim_version
  end

  test "cancelled blockers remain incomplete" do
    project = create_project
    blocker = create_task(project:)
    blocked = create_task(project:)
    TaskDependency.create!(task: blocked, blocker:)
    @lifecycle.cancel!(task_id: blocker.id)

    assert_nil @lifecycle.claim_next!(project:, owner_id: "session")
  end

  test "a completed blocker makes its dependent available" do
    project = create_project
    blocker = create_task(project:)
    blocked = create_task(project:)
    TaskDependency.create!(task: blocked, blocker:)
    claim = @lifecycle.claim_next!(project:, owner_id: "session")
    advanced = @lifecycle.report_attempt!(task_id: claim.id, owner_id: "session", claim_version: claim.claim_version,
      step: "develop", outcome: "ready", artifact: "# Develop")
    @lifecycle.report_attempt!(task_id: claim.id, owner_id: "session", claim_version: advanced.claim_version,
      step: "check", outcome: "passed", artifact: "# Check")

    assert_equal blocked, @lifecycle.claim_next!(project:, owner_id: "session-2")
  end

  test "reports next steps pauses and completion" do
    task = claim_task(owner_id: "session")

    advanced = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
      step: "develop", outcome: "ready", artifact: "# Develop")
    assert_equal "check", advanced.current_step
    assert_equal 2, advanced.claim_version
    assert_equal "active", advanced.status
    assert_equal "session", advanced.owner_id

    paused = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 2,
      step: "check", outcome: "blocked", artifact: "# Blocked", message: "CI is unavailable")
    assert_equal "blocked", paused.status
    assert_equal "check", paused.current_step
    assert_equal 3, paused.claim_version
    assert_nil paused.owner_id
    assert_nil paused.lease_expires_at

    resumed = @lifecycle.resume!(task_id: task.id, owner_id: "session-2", claim_version: 3, step: "check")
    completed = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session-2",
      claim_version: resumed.claim_version, step: "check", outcome: "passed", artifact: "# Passed")
    assert_equal "completed", completed.status
    assert_nil completed.owner_id
  end

  test "legacy built-in publish snapshots cannot complete without verification" do
    BuiltInCatalog.install!

    TaskLifecycle::BUILT_IN_TASK_KEYS.each do |key|
      task_type = TaskType.find_by!(key:)
      definition = BuiltInCatalog.definitions.fetch(key).deep_dup
      definition["steps"].reject! { |candidate| candidate["id"] == "verify" }
      publish = definition["steps"].find { |candidate| candidate["id"] == "publish" }
      publish["outcomes"]["published"] = { "complete_task" => true }
      publish["outcomes"].delete("review_invalid")
      legacy_workflow = create_workflow(name: "Pre-PLAN-022 #{key}", definition:)
      task_type.update!(workflow: legacy_workflow)
      task = create_task(project: create_project, workflow: legacy_workflow, task_type:, current_step: "publish")
      task = @lifecycle.claim!(task_id: task.id, owner_id: "#{key}-owner")
      before = task.attributes

      error = assert_raises(TaskLifecycle::InvalidTransition) do
        @lifecycle.report_attempt!(task_id: task.id, owner_id: task.owner_id,
          claim_version: task.claim_version, step: "publish", outcome: "published", artifact: "# Published")
      end

      assert_match(/complete only from verify/, error.message)
      assert_equal before, task.reload.attributes
      assert_equal legacy_workflow.id, task.workflow_id
      assert_equal legacy_workflow.definition_json, task.workflow.definition_json
      assert_empty task.accepted_artifacts
    end
  end

  test "rejects stale identity expired leases wrong steps and unknown outcomes without mutation" do
    task = claim_task(owner_id: "session")
    original = task.attributes

    invalid_reports = [
      { owner_id: "stale", claim_version: 1, step: "develop", outcome: "ready" },
      { owner_id: "session", claim_version: 0, step: "develop", outcome: "ready" },
      { owner_id: "session", claim_version: 1, step: "check", outcome: "passed" }
    ]
    invalid_reports.each do |report|
      assert_raises(TaskLifecycle::Conflict) do
        @lifecycle.report_attempt!(task_id: task.id, artifact: "# Attempt", **report)
      end
      assert_equal original, task.reload.attributes
    end

    assert_raises(TaskLifecycle::InvalidTransition) do
      @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
        step: "develop", outcome: "missing", artifact: "# Missing")
    end
    assert_equal original, task.reload.attributes

    @now += 2.hours
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
        step: "develop", outcome: "ready", artifact: "# Expired")
    end
    assert_equal original, task.reload.attributes
  end

  test "resume replaces paused or expired ownership but requires confirmation for a live owner" do
    task = claim_task(owner_id: "session-1")

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.resume!(task_id: task.id, owner_id: "session-2", claim_version: 1, step: "develop")
    end
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.resume!(task_id: task.id, owner_id: "session-2", claim_version: 1, step: "develop",
        takeover_confirmed: "true")
    end

    replaced = @lifecycle.resume!(task_id: task.id, owner_id: "session-2", claim_version: 1, step: "develop",
      takeover_confirmed: true)
    assert_equal 2, replaced.claim_version
    assert_equal "develop", replaced.current_step

    @now += 2.hours
    resumed = @lifecycle.resume!(task_id: task.id, owner_id: "session-3", claim_version: 2, step: "develop")
    assert_equal 3, resumed.claim_version
    assert_equal "session-3", resumed.owner_id
  end

  test "cancelling an active task fences and releases its owner" do
    task = claim_task(owner_id: "session")

    cancelled = @lifecycle.cancel!(task_id: task.id)

    assert_equal "cancelled", cancelled.status
    assert_equal 2, cancelled.claim_version
    assert_nil cancelled.owner_id
    assert_nil cancelled.lease_expires_at
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
        step: "develop", outcome: "ready", artifact: "# Stale")
    end
  end

  test "terminal tasks cannot be resumed or cancelled" do
    task = claim_task(owner_id: "session")
    @lifecycle.cancel!(task_id: task.id)

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.resume!(task_id: task.id, owner_id: "new", claim_version: 1, step: "develop")
    end
    assert_raises(TaskLifecycle::Conflict) { @lifecycle.cancel!(task_id: task.id) }
  end

  test "requires a non-empty owner" do
    project = create_project
    create_task(project:)

    assert_raises(ArgumentError) { @lifecycle.claim_next!(project:, owner_id: "") }
  end

  test "the same report cannot be accepted twice for a self-transition" do
    definition = valid_workflow_definition
    definition["steps"][0]["outcomes"]["again"] = { "next_step" => "develop" }
    project = create_project
    workflow = create_workflow(definition:)
    task_type = create_task_type(workflow:)
    create_task(project:, workflow:, task_type:)
    task = @lifecycle.claim_next!(project:, owner_id: "session")

    accepted = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
      step: "develop", outcome: "again", artifact: "# First")
    assert_equal "develop", accepted.current_step
    assert_equal 2, accepted.claim_version

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
        step: "develop", outcome: "again", artifact: "# Duplicate")
    end
  end

  test "accepted artifacts transition atomically and a repeated successful step replaces its record" do
    definition = valid_workflow_definition
    definition["steps"][0]["outcomes"]["again"] = { "next_step" => "develop" }
    workflow = create_workflow(definition:)
    task = create_task(workflow:, task_type: create_task_type(workflow:))
    task = @lifecycle.claim!(task_id: task.id, owner_id: "session")

    task = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
      step: "develop", outcome: "again", artifact: "# First")
    task = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 2,
      step: "develop", outcome: "again", artifact: "# Second")

    assert_equal 3, task.claim_version
    assert_equal({
      "outcome" => "again", "markdown" => "# Second", "accepted_claim_version" => 2, "reconstructed" => false
    }, task.accepted_artifacts.fetch("develop"))

    before = task.attributes
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 2,
        step: "develop", outcome: "again", artifact: "# Stale")
    end
    assert_equal before, task.reload.attributes
  end

  test "validates artifact bytes before changing task state" do
    task = claim_task(owner_id: "session")
    invalid_utf8 = "\xFF".b.force_encoding(Encoding::UTF_8)

    [ nil, "", invalid_utf8, "x" * (TaskLifecycle::MAX_ARTIFACT_BYTES + 1) ].each do |artifact|
      assert_raises(TaskLifecycle::InvalidInput) do
        @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
          step: "develop", outcome: "ready", artifact:)
      end
      assert_equal({}, task.reload.accepted_artifacts)
      assert_equal 1, task.claim_version
    end
  end

  test "binds a human answer to the exact paused claim and clears it after transition" do
    task = claim_task(owner_id: "session")
    task = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
      step: "develop", outcome: "question", artifact: "# Question", message: "Which option?")

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.resume!(task_id: task.id, owner_id: "new", claim_version: 1, step: "develop", answer: "A")
    end
    assert_nil task.reload.human_answer
    assert_raises(TaskLifecycle::InvalidInput) do
      @lifecycle.resume!(task_id: task.id, owner_id: "new", claim_version: 2, step: "develop")
    end

    task = @lifecycle.resume!(task_id: task.id, owner_id: "new", claim_version: 2, step: "develop", answer: "A")
    reloaded = Task.find(task.id)
    assert_equal "A", reloaded.human_answer
    assert_equal "develop", reloaded.human_answer_step
    assert_equal 2, reloaded.human_answer_claim_version

    task = @lifecycle.report_attempt!(task_id: task.id, owner_id: "new", claim_version: 3,
      step: "develop", outcome: "ready", artifact: "# Decision")
    assert_equal "check", task.current_step
    assert_nil task.human_answer
    assert_nil task.pause_message
  end

  private

  def claim_task(owner_id:)
    project = create_project
    create_task(project:)
    @lifecycle.claim_next!(project:, owner_id:)
  end
end

class TaskLifecycleConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    TaskDependency.delete_all
    Task.delete_all
    TaskType.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  teardown do
    TaskDependency.delete_all
    Task.delete_all
    TaskType.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  test "two sessions cannot claim the same task" do
    project = create_project
    task = create_task(project:)
    selected = Queue.new
    release = Queue.new
    results = Queue.new

    coordinated_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @selected = selected
        @release = release
        @coordinated = false
      end

      private

      define_method(:next_claimable_id) do |eligible|
        task_id = super(eligible)
        return task_id if @coordinated

        @coordinated = true
        @selected << task_id
        @release.pop
        task_id
      end
    end

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          result = coordinated_lifecycle.new.claim_next!(project:, task_type: task.task_type,
            owner_id: "session-#{index}")
        rescue StandardError => error
          result = error
        ensure
          results << result
        end
      end
    end
    chosen_ids = Timeout.timeout(5) { 2.times.map { selected.pop } }
    assert_equal [ task.id, task.id ], chosen_ids
    2.times { release << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }
    errors = outcomes.grep(StandardError)
    claims = outcomes.compact - errors

    assert_empty errors
    assert_equal [ task.id ], claims.map(&:id)
    assert_equal 1, task.reload.claim_version
    assert_includes %w[session-0 session-1], task.owner_id
  end

  test "two sessions cannot claim the same exact task" do
    task = create_task
    selected = Queue.new
    release = Queue.new
    results = Queue.new
    coordinated_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @selected = selected
        @release = release
      end

      private

      define_method(:claim_from_scope) do |scope, **arguments|
        @selected << true
        @release.pop
        super(scope, **arguments)
      end
    end

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          result = coordinated_lifecycle.new.claim!(task_id: task.id, owner_id: "session-#{index}")
        rescue StandardError => error
          result = error
        ensure
          results << result
        end
      end
    end
    Timeout.timeout(5) { 2.times { selected.pop } }
    2.times { release << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }

    assert_equal 1, outcomes.grep(Task).size
    assert_equal 1, outcomes.grep(TaskLifecycle::Conflict).size
    assert_equal 1, task.reload.claim_version
  end

  test "concurrent identical create and claim requests return one task" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    transaction_acquired = Queue.new
    release = Queue.new
    second_started = Queue.new
    results = Queue.new
    arguments = {
      project:, task_type:, title: "Created", description_markdown: "Description", owner_id: "session"
    }
    coordinated_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @transaction_acquired = transaction_acquired
        @release = release
      end

      private

      define_method(:create_claimed_task!) do |**attributes|
        @transaction_acquired << true
        @release.pop
        super(**attributes)
      end
    end

    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        result = coordinated_lifecycle.new.create_and_claim!(**arguments)
      rescue StandardError => error
        result = error
      ensure
        results << result
      end
    end
    Timeout.timeout(5) { transaction_acquired.pop }
    second = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        second_started << true
        result = TaskLifecycle.new.create_and_claim!(**arguments)
      rescue StandardError => error
        result = error
      ensure
        results << result
      end
    end
    Timeout.timeout(5) { second_started.pop }
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { results.pop } }
    release << true
    first.join
    second.join
    outcomes = 2.times.map { results.pop }

    assert_empty outcomes.grep(StandardError)
    assert_equal 1, outcomes.map(&:id).uniq.size
    assert_equal 1, Task.where(project:, owner_id: "session").count
  end

  test "concurrent creation-key requests with different owners return one task" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    gate = Queue.new
    results = Queue.new
    arguments = {
      project:, task_type:, title: "Created", description_markdown: "Description",
      creation_key: "request:brief:sha256:concurrent"
    }

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          result = TaskLifecycle.new.create_and_claim!(**arguments, owner_id: "session-#{index}")
        rescue StandardError => error
          result = error
        ensure
          results << result
        end
      end
    end
    2.times { gate << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }

    assert_empty outcomes.grep(StandardError)
    assert_equal 1, outcomes.map(&:id).uniq.size
    assert_equal 1, Task.where(project:, task_type:, creation_key: arguments[:creation_key]).count
  end

  test "the same claim cannot report one transition twice concurrently" do
    project = create_project
    create_task(project:)
    task = TaskLifecycle.new.claim_next!(project:, owner_id: "session")
    gate = Queue.new
    results = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          result = TaskLifecycle.new.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
            step: "develop", outcome: "ready", artifact: "# Concurrent")
        rescue StandardError => error
          result = error
        ensure
          results << result
        end
      end
    end
    2.times { gate << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }

    assert_equal 1, outcomes.grep(Task).size
    assert_equal 1, outcomes.grep(TaskLifecycle::Conflict).size
    assert_equal "check", task.reload.current_step
    assert_equal 2, task.claim_version
  end

  test "cancellation and reporting leave one fenced final state" do
    project = create_project
    create_task(project:)
    task = TaskLifecycle.new.claim_next!(project:, owner_id: "session")
    gate = Queue.new
    results = Queue.new
    operations = {
      report: -> {
        TaskLifecycle.new.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
          step: "develop", outcome: "ready", artifact: "# Concurrent")
      },
      cancel: -> { TaskLifecycle.new.cancel!(task_id: task.id) }
    }

    threads = operations.map do |name, operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          result = operation.call
        rescue StandardError => error
          result = error
        ensure
          results << [ name, result ]
        end
      end
    end
    2.times { gate << true }
    threads.each(&:join)
    outcomes = 2.times.to_h { results.pop }

    assert_instance_of Task, outcomes.fetch(:cancel)
    assert_includes [ Task, TaskLifecycle::Conflict ], outcomes.fetch(:report).class
    assert_equal "cancelled", task.reload.status
    assert_nil task.owner_id
    assert_operator task.claim_version, :>=, 2
  end

  test "definition editing serializes with a concurrent claim" do
    project = create_project
    task = create_task(project:)
    edit_locked = Queue.new
    release_edit = Queue.new
    claim_selected = Queue.new
    release_claim = Queue.new
    results = Queue.new

    editing_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @edit_locked = edit_locked
        @release_edit = release_edit
      end

      private

      define_method(:lock_editable_task!) do |task_id|
        editable_task = super(task_id)
        @edit_locked << true
        @release_edit.pop
        editable_task
      end
    end
    claiming_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @claim_selected = claim_selected
        @release_claim = release_claim
      end

      private

      define_method(:next_claimable_id) do |eligible|
        task_id = super(eligible)
        @claim_selected << true
        @release_claim.pop
        task_id
      end
    end

    editor = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << editing_lifecycle.new.update_definition!(task_id: task.id, description_markdown: "Updated")
      rescue StandardError => error
        results << error
      end
    end
    Timeout.timeout(5) { edit_locked.pop }
    claimant = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << claiming_lifecycle.new.claim_next!(project:, owner_id: "session")
      rescue StandardError => error
        results << error
      end
    end
    Timeout.timeout(5) { claim_selected.pop }
    release_claim << true
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { results.pop } }
    release_edit << true
    editor.join
    claimant.join
    outcomes = 2.times.map { results.pop }

    assert_empty outcomes.grep(StandardError)
    assert_equal "Updated", task.reload.description_markdown
    assert_equal "active", task.status
    assert_equal "session", task.owner_id
  end

  test "a definition edit conflicts when a concurrent claim wins" do
    project = create_project
    task = create_task(project:)
    claim_locked = Queue.new
    release_claim = Queue.new
    edit_started = Queue.new
    results = Queue.new

    claiming_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @claim_locked = claim_locked
        @release_claim = release_claim
      end

      define_method(:claim_next!) do |**arguments|
        Task.transaction do
          claimed = super(**arguments)
          @claim_locked << true
          @release_claim.pop
          claimed
        end
      end
    end

    claimant = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << claiming_lifecycle.new.claim_next!(project:, owner_id: "session")
      rescue StandardError => error
        results << error
      end
    end
    Timeout.timeout(5) { claim_locked.pop }
    editor = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        edit_started << true
        results << TaskLifecycle.new.update_definition!(task_id: task.id, description_markdown: "Too late")
      rescue StandardError => error
        results << error
      end
    end
    Timeout.timeout(5) { edit_started.pop }
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { results.pop } }
    release_claim << true
    claimant.join
    editor.join
    outcomes = 2.times.map { results.pop }

    assert_equal 1, outcomes.grep(Task).size
    assert_equal 1, outcomes.grep(TaskLifecycle::Conflict).size
    assert_equal "Description", task.reload.description_markdown
    assert_equal "active", task.status
  end
end
