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

  test "requires authentication on all task routes" do
    requests = [
      -> { put project_plan_path(1), params: {}, as: :json },
      -> { get project_plan_path(1) },
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
