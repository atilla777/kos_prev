require "test_helper"

class TasksApiTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-api-token" }
    @project = create_project
    @workflow = create_workflow(key: "delivery")
  end

  test "stores shows and replaces an atomic task plan" do
    put project_plan_path(@project), params: plan_parameters.except(:project_id), headers: @headers, as: :json
    assert_response :success
    assert_equal "release", response.parsed_body.dig("task_plan", "key")
    assert_equal %w[first second], response.parsed_body.fetch("tasks").pluck("key")
    assert_equal [ "first" ], response.parsed_body.fetch("tasks").last.fetch("blocker_keys")

    get project_plan_path(@project), params: { key: "release" }, headers: @headers
    assert_response :success

    assert_no_difference -> { TaskPlan.count } do
      put project_plan_path(@project), params: plan_parameters.except(:project_id).merge(title: "Replacement", tasks: [
        plan_task(key: "only", workflow: @workflow)
      ]), headers: @headers, as: :json
    end
    assert_response :success
    assert_equal [ "only" ], response.parsed_body.fetch("tasks").pluck("key")
  end

  test "rejects an invalid plan without partial writes" do
    parameters = plan_parameters.merge(tasks: [
      plan_task(key: "a", workflow: @workflow, blockers: [ "b" ]),
      plan_task(key: "b", workflow: @workflow, blockers: [ "a" ])
    ])
    assert_no_difference [ -> { TaskPlan.count }, -> { Task.count }, -> { TaskDependency.count } ] do
      put project_plan_path(@project), params: parameters.except(:project_id), headers: @headers, as: :json
    end
    assert_response :bad_request
  end

  test "identifies an unknown workflow key without replacing an existing plan" do
    put project_plan_path(@project), params: plan_parameters.except(:project_id), headers: @headers, as: :json
    original = TaskPlan.find_by!(project: @project, key: "release")
    original_task_ids = original.tasks.order(:id).ids

    assert_no_difference [ -> { TaskPlan.count }, -> { Task.count }, -> { TaskDependency.count } ] do
      put project_plan_path(@project), params: plan_parameters.except(:project_id).merge(tasks: [
        plan_task(key: "unknown", workflow: @workflow).merge("workflow_key" => "missing-workflow")
      ]), headers: @headers, as: :json
    end

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.fetch("error")
    assert_includes response.parsed_body.fetch("message"), "missing-workflow"
    assert_equal original_task_ids, original.reload.tasks.order(:id).ids
  end

  test "exposes ready state and the focused worker context and result" do
    put project_plan_path(@project), params: plan_parameters.except(:project_id), headers: @headers, as: :json
    tasks = response.parsed_body.fetch("tasks")
    first = tasks.first

    get tasks_ready_path, params: { project_id: @project.id }, headers: @headers
    assert_response :success
    assert_equal [ "first" ], response.parsed_body.fetch("tasks").pluck("key")

    post claim_task_path(first.fetch("id")), params: { claim_id: "worker", version: 0 }, headers: @headers, as: :json
    assert_response :success
    assert_equal 1, response.parsed_body.dig("task", "version")

    get context_task_path(first.fetch("id")), headers: @headers
    assert_response :success
    assert_equal "Do first", response.parsed_body.dig("task", "description_markdown")
    assert_equal %w[blocked done question], response.parsed_body.dig("step", "allowed_outcomes").sort
    assert_equal({ "next_step" => "review" }, response.parsed_body.dig("step", "outcomes", "done"))

    post report_task_path(first.fetch("id")), params: {
      claim_id: "worker", version: 1, step: "work", outcome: "done", result: "Implemented"
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "pending", response.parsed_body.dig("task", "status")
    assert_nil response.parsed_body.dig("task", "claim_id")

    get result_task_path(first.fetch("id")), params: { step: "work" }, headers: @headers
    assert_response :success
    assert_equal({ "outcome" => "done", "result" => "Implemented" }, response.parsed_body)
  end

  test "supports exact takeover pause and answer fences" do
    task = create_task(project: @project, workflow: @workflow)
    post claim_task_path(task), params: { claim_id: "first", version: 0 }, headers: @headers, as: :json

    post takeover_task_path(task), params: { claim_id: "second", version: 1, step: "work" },
      headers: @headers, as: :json
    assert_response :success
    assert_equal 2, response.parsed_body.dig("task", "version")

    post report_task_path(task), params: {
      claim_id: "first", version: 1, step: "work", outcome: "question", result: "Stale", message: "Question"
    }, headers: @headers, as: :json
    assert_response :conflict

    post report_task_path(task), params: {
      claim_id: "second", version: 2, step: "work", outcome: "question", result: "Need input",
      message: "Which option?"
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "needs_human", response.parsed_body.dig("task", "status")

    post answer_task_path(task), params: { version: 3, step: "work", answer: "A" }, headers: @headers, as: :json
    assert_response :success
    assert_equal [ "pending", "A", 4 ], response.parsed_body.fetch("task").values_at("status", "answer", "version")
  end

  test "abandons a started plan through an exact plan fence" do
    plan = create_task_plan(project: @project, key: "obsolete")
    completed = create_task(task_plan: plan, workflow: @workflow, key: "completed")
    completed.update!(status: "completed", accepted_results: {
      "work" => { "outcome" => "done", "result" => "kept" }
    })
    active = create_task(task_plan: plan, workflow: @workflow, key: "active")
    active.update!(status: "active", claim_id: "worker", version: 2)

    post abandon_project_plan_path(@project), params: { key: plan.key, version: 0 }, headers: @headers, as: :json
    assert_response :success
    assert_equal [ "abandoned", 1 ], response.parsed_body.fetch("task_plan").values_at("status", "version")
    assert_equal [ "completed", "abandoned" ], response.parsed_body.fetch("tasks").pluck("status")
    assert_nil response.parsed_body.fetch("tasks").last.fetch("claim_id")

    post report_task_path(active), params: {
      claim_id: "worker", version: 2, step: "work", outcome: "done", result: "stale"
    }, headers: @headers, as: :json
    assert_response :conflict
    post abandon_project_plan_path(@project), params: { key: plan.key, version: 0 }, headers: @headers, as: :json
    assert_response :conflict

    post abandon_project_plan_path(@project), params: { key: plan.key }, headers: @headers, as: :json
    assert_response :bad_request

    get tasks_ready_path, params: { project_id: @project.id }, headers: @headers
    assert_empty response.parsed_body.fetch("tasks")
    get result_task_path(completed), params: { step: "work" }, headers: @headers
    assert_equal "kept", response.parsed_body.fetch("result")
  end

  test "discovers project plans and unfinished task lifecycle state" do
    plan = create_task_plan(project: @project, key: "current")
    pending = create_task(task_plan: plan, workflow: @workflow, key: "pending")
    pending.update!(pause_kind: "needs_human", pause_message: "Choose", pause_step: "work", answer: "A", version: 4)
    active = create_task(task_plan: plan, workflow: @workflow, key: "active")
    active.update!(status: "active", claim_id: "worker", version: 2)
    paused = create_task(task_plan: plan, workflow: @workflow, key: "paused")
    paused.update!(status: "needs_human", pause_kind: "needs_human", pause_message: "Which option?",
      pause_step: "work", version: 3)
    blocked = create_task(task_plan: plan, workflow: @workflow, key: "blocked")
    blocked.update!(status: "blocked", pause_kind: "blocked", pause_message: "Service unavailable",
      pause_step: "work", version: 5)
    TaskDependency.create!(task: blocked, blocker: active)
    completed_plan = create_task_plan(project: @project, key: "finished")
    completed = create_task(task_plan: completed_plan, workflow: @workflow, key: "completed")
    completed.update!(status: "completed", current_step: "review", version: 6)
    create_task(project: create_project(name: "Other"), workflow: @workflow, key: "other")

    get project_plans_path(@project), headers: @headers
    assert_response :success
    assert_equal [ "current" ], response.parsed_body.fetch("task_plans").pluck("key")

    get project_tasks_path(@project), headers: @headers
    assert_response :success
    tasks = response.parsed_body.fetch("tasks")
    assert_equal %w[pending active paused blocked], tasks.pluck("key")
    assert_equal [ active.id, "work", 2, "worker" ],
      tasks.find { |task| task["key"] == "active" }.values_at("id", "current_step", "version", "claim_id")
    assert_equal [ "needs_human", "Which option?", "work", nil ],
      tasks.find { |task| task["key"] == "paused" }.values_at("pause_kind", "pause_message", "pause_step", "answer")
    assert_equal [ "needs_human", "Choose", "work", "A" ],
      tasks.find { |task| task["key"] == "pending" }.values_at("pause_kind", "pause_message", "pause_step", "answer")
    assert_equal [ @workflow.id, "delivery", @workflow.revision ],
      tasks.first.values_at("workflow_id", "workflow_key", "workflow_revision")

    get tasks_ready_path, params: { project_id: @project.id }, headers: @headers
    ready = response.parsed_body.fetch("tasks").first
    assert_equal [ @workflow.id, "delivery", @workflow.revision ],
      ready.values_at("workflow_id", "workflow_key", "workflow_revision")

    get task_path(active), headers: @headers
    assert_equal [ @workflow.id, "delivery", @workflow.revision ],
      response.parsed_body.fetch("task").values_at("workflow_id", "workflow_key", "workflow_revision")

    get project_plans_path(@project), params: { include_completed: true }, headers: @headers
    assert_equal %w[current finished], response.parsed_body.fetch("task_plans").pluck("key")
    get project_tasks_path(@project), params: { include_completed: true }, headers: @headers
    assert_equal %w[pending active paused blocked completed], response.parsed_body.fetch("tasks").pluck("key")

    get coordination_status_path, params: { repository_identity: @project.repository_identity }, headers: @headers
    assert_response :success
    status = response.parsed_body
    assert_equal @project.id, status.dig("project", "id")
    assert_equal [ "current" ], status.fetch("task_plans").pluck("key")
    assert_equal %w[pending active paused blocked], status.fetch("tasks").pluck("key")
    assert_equal [ "worker", 2 ], status.fetch("tasks").second.values_at("claim_id", "version")
    assert_equal [ "needs_human", "Which option?", "work", nil ],
      status.fetch("tasks").third.values_at("pause_kind", "pause_message", "pause_step", "answer")
    assert_equal [ @workflow.id, "delivery", @workflow.revision ],
      status.fetch("tasks").first.values_at("workflow_id", "workflow_key", "workflow_revision")
    assert_equal [ active.id ], status.fetch("tasks").last.fetch("blocker_ids")
  end

  test "validates discovery filters and project scope" do
    get project_tasks_path(@project), params: { include_completed: "yes" }, headers: @headers
    assert_response :bad_request
    assert_equal "include_completed must be true or false", response.parsed_body.fetch("message")

    get project_plans_path(0), headers: @headers
    assert_response :not_found

    other_plan = create_task_plan(project: create_project(name: "Other project"), key: "other-plan")
    get tasks_ready_path, params: { project_id: @project.id, task_plan_id: other_plan.id }, headers: @headers
    assert_response :not_found
    assert_includes response.parsed_body.fetch("message"), other_plan.id.to_s
    assert_includes response.parsed_body.fetch("message"), @project.id.to_s

    get coordination_status_path, params: { repository_identity: "example.test/missing/project" }, headers: @headers
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.fetch("error")
    assert_includes response.parsed_body.fetch("message"), "example.test/missing/project"
  end

  test "identifies missing plans tasks and results by lookup value" do
    get project_plan_path(@project), params: { key: "missing-plan" }, headers: @headers
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.fetch("error")
    assert_includes response.parsed_body.fetch("message"), "missing-plan"

    get task_path(123_456), headers: @headers
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.fetch("error")
    assert_includes response.parsed_body.fetch("message"), "123456"

    task = create_task(project: @project, workflow: @workflow)
    get result_task_path(task), params: { step: "missing-step" }, headers: @headers
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.fetch("error")
    assert_includes response.parsed_body.fetch("message"), task.id.to_s
    assert_includes response.parsed_body.fetch("message"), "missing-step"
  end

  test "requires authentication on all task routes" do
    requests = [
      -> { put project_plan_path(1), params: {}, as: :json },
      -> { get project_plan_path(1) },
      -> { get project_plans_path(1) },
      -> { post abandon_project_plan_path(1), params: {}, as: :json },
      -> { get project_tasks_path(1) },
      -> { get coordination_status_path },
      -> { get tasks_ready_path },
      -> { get task_path(1) },
      -> { get context_task_path(1) },
      -> { get result_task_path(1) },
      -> { post claim_task_path(1), params: {}, as: :json },
      -> { post takeover_task_path(1), params: {}, as: :json },
      -> { post report_task_path(1), params: {}, as: :json },
      -> { post answer_task_path(1), params: {}, as: :json }
    ]
    requests.each do |request|
      request.call
      assert_response :unauthorized
    end
  end

  private

  def plan_parameters
    {
      project_id: @project.id, key: "release", title: "Release", tasks: [
        plan_task(key: "first", workflow: @workflow),
        plan_task(key: "second", workflow: @workflow, blockers: [ "first" ])
      ]
    }
  end
end
