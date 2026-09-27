require "test_helper"

class TasksApiTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-api-token" }
    @project = create_project
    @workflow = create_workflow
    @task_type = create_task_type(name: "Feature", workflow: @workflow)
  end

  test "creates and shows a task with its workflow current step and dependencies" do
    parent = create_task(project: @project, workflow: @workflow, task_type: @task_type, title: "Parent")
    blocker = create_task(project: @project, workflow: @workflow, task_type: @task_type, title: "Blocker")

    post tasks_path, params: task_parameters.merge(parent_id: parent.id, blocker_ids: [ blocker.id ]),
      headers: @headers, as: :json

    assert_response :created
    task_id = response.parsed_body.dig("task", "id")
    assert_equal parent.id, response.parsed_body.dig("task", "parent_id")
    assert_equal [ blocker.id ], response.parsed_body.dig("task", "blocker_ids")
    assert_equal @workflow.id, response.parsed_body.dig("workflow", "id")
    assert_equal "develop", response.parsed_body.dig("step", "id")
    assert_equal "advanced", response.parsed_body.dig("step", "model_tier")
    assert_equal "main", response.parsed_body.dig("step", "execution_mode")
    assert_equal "Implement the task.", response.parsed_body.dig("step", "instruction")

    get task_path(task_id), headers: @headers, as: :json
    assert_response :success
    assert_equal task_id, response.parsed_body.dig("task", "id")
  end

  test "creates tasks by type key while preserving numeric creation" do
    post tasks_path, params: task_parameters.except(:task_type_id).merge(task_type_key: @task_type.key),
      headers: @headers, as: :json

    assert_response :created
    assert_equal @task_type.id, response.parsed_body.dig("task", "task_type_id")
    assert_equal @task_type.key, response.parsed_body.dig("task", "task_type_key")

    post tasks_path, params: task_parameters.merge(task_type_key: @task_type.key), headers: @headers, as: :json
    assert_response :bad_request

    post tasks_path, params: task_parameters.except(:task_type_id).merge(task_type_key: "missing"),
      headers: @headers, as: :json
    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]
  end

  test "context returns the bounded agent projection and artifact bodies are read separately" do
    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    lifecycle = TaskLifecycle.new
    task = lifecycle.claim!(task_id: task.id, owner_id: "session")
    lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
      step: "develop", outcome: "question", artifact: "# Private artifact", message: "Choose a mode")

    get context_task_path(task), headers: @headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal %w[claim_version current_step description_markdown id lease_expires_at owner_id project_id status title],
      body.fetch("task").keys.sort
    assert_equal %w[default_branch id name remote_url repository_identity], body.fetch("project").keys.sort
    assert_equal @project.repository_identity, body.dig("project", "repository_identity")
    assert_equal %w[allowed_outcomes artifact_template execution_mode id instruction model_tier name],
      body.fetch("step").keys.sort
    assert_equal %w[question ready], body.dig("step", "allowed_outcomes").sort
    assert_equal [ {
      "step" => "develop", "outcome" => "question", "accepted_claim_version" => 1, "reconstructed" => false
    } ], body.fetch("artifacts")
    assert_not_includes body.to_json, "Private artifact"
    assert_equal "Choose a mode", body.dig("pause", "message")

    get artifact_task_path(task), params: { step: "develop" }, headers: @headers
    assert_response :success
    assert_equal({
      "outcome" => "question", "markdown" => "# Private artifact", "accepted_claim_version" => 1,
      "reconstructed" => false
    }, response.parsed_body)

    get artifact_task_path(task), params: { step: "check" }, headers: @headers
    assert_response :not_found
  end

  test "stale owner claim and wrong step reports atomically leave state and artifacts unchanged" do
    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    task = TaskLifecycle.new.claim!(task_id: task.id, owner_id: "session")
    before = task.attributes

    [
      { owner_id: "wrong", claim_version: 1, step: "develop", outcome: "ready" },
      { owner_id: "session", claim_version: 0, step: "develop", outcome: "ready" },
      { owner_id: "session", claim_version: 1, step: "check", outcome: "passed" }
    ].each do |identity|
      post report_attempt_task_path(task), params: identity.merge(artifact: "# Rejected"), headers: @headers, as: :json

      assert_response :conflict
      assert_equal before, task.reload.attributes
      assert_empty task.accepted_artifacts
    end
  end

  test "creates and claims idempotently by owner and exact definition" do
    parameters = task_parameters.except(:task_type_id).merge(task_type_key: @task_type.key, owner_id: "session")

    post tasks_create_and_claim_path, params: parameters, headers: @headers, as: :json
    assert_response :created
    task_id = response.parsed_body.dig("task", "id")

    assert_no_difference -> { Task.count } do
      post tasks_create_and_claim_path, params: parameters, headers: @headers, as: :json
    end
    assert_response :created
    assert_equal task_id, response.parsed_body.dig("task", "id")

    post tasks_create_and_claim_path, params: parameters.merge(title: "Different"), headers: @headers, as: :json
    assert_response :conflict
  end

  test "creates and claims idempotently by request key across owners without changing the response" do
    parameters = task_parameters.except(:task_type_id).merge(
      task_type_key: @task_type.key, owner_id: "first", creation_key: "request:fix:sha256:api"
    )

    post tasks_create_and_claim_path, params: parameters, headers: @headers, as: :json
    assert_response :created
    first_body = response.parsed_body
    task = Task.find(first_body.dig("task", "id"))
    TaskLifecycle.new.report_attempt!(task_id: task.id, owner_id: "first", claim_version: task.claim_version,
      step: "develop", outcome: "ready", artifact: "# Progressed")
    before = task.reload.attributes

    assert_no_difference -> { Task.count } do
      post tasks_create_and_claim_path, params: parameters.merge(owner_id: "second"), headers: @headers, as: :json
    end
    assert_response :created
    assert_equal first_body.fetch("task").keys.sort, response.parsed_body.fetch("task").keys.sort
    refute_includes response.parsed_body.fetch("task"), "creation_key"
    assert_equal task.id, response.parsed_body.dig("task", "id")
    assert_equal before, task.reload.attributes

    post tasks_create_and_claim_path, params: parameters.merge(owner_id: "third", title: "Different"),
      headers: @headers, as: :json
    assert_response :conflict
  end

  test "creates or gets a canonical request-bound task including existing keyed tasks" do
    BuiltInCatalog.install!
    fix_type = TaskType.find_by!(key: "fix")
    request = "  Preserve exact whitespace  \nsecond line"
    key = "request:fix:sha256:#{Digest::SHA256.hexdigest(request)}"
    existing = TaskLifecycle.new.create_and_claim!(project: @project, task_type: fix_type,
      title: "Fix: Preserve exact whitespace", description_markdown: "# Problem\n\n#{request}\n",
      owner_id: "legacy-owner", creation_key: key)
    before = existing.attributes

    assert_no_difference -> { Task.count } do
      post tasks_create_or_get_path,
        params: { project_id: @project.id, kind: "fix", request:, owner_id: "new-owner" }, headers: @headers, as: :json
    end

    assert_response :success
    assert_equal existing.id, response.parsed_body.dig("task", "id")
    assert_equal before, existing.reload.attributes

    post tasks_create_or_get_path,
      params: { project_id: @project.id, kind: "other", request:, owner_id: "owner" }, headers: @headers, as: :json
    assert_response :bad_request
  end

  test "atomically materializes and observes a brief child graph" do
    brief, claim = claimed_brief_at_publish
    children = [
      { key: "core", title: "Core", description_markdown: "Build core", blocker_keys: [] },
      { key: "surface", title: "Surface", description_markdown: "Build surface", blocker_keys: [ "core" ] }
    ]

    assert_difference -> { Task.count }, 2 do
      post materialize_children_task_path(brief), params: {
        owner_id: "brief-owner", claim_version: claim.claim_version, children:
      }, headers: @headers, as: :json
    end
    assert_response :created
    digest = response.parsed_body.fetch("digest")
    assert_equal "created", response.parsed_body.fetch("materialization")
    assert_match(/\Asha256:[0-9a-f]{64}\z/, digest)
    materialized = response.parsed_body.fetch("children")
    assert_equal [ "Core", "Surface" ], materialized.map { |entry| entry.dig("task", "title") }

    core_id = materialized.find { |entry| entry.dig("task", "title") == "Core" }.dig("task", "id")
    patch task_path(core_id), params: { parent_id: nil, blocker_ids: [] }, headers: @headers, as: :json
    assert_response :conflict

    post tasks_path, params: task_parameters.merge(parent_id: brief.id), headers: @headers, as: :json
    assert_response :conflict

    get children_task_path(brief), headers: @headers, as: :json
    assert_response :success
    assert_equal digest, response.parsed_body.fetch("digest")
    observed = response.parsed_body.fetch("children")
    core_id = observed.find { |entry| entry.dig("task", "title") == "Core" }.dig("task", "id")
    surface = observed.find { |entry| entry.dig("task", "title") == "Surface" }
    assert_equal [ core_id ], surface.fetch("sibling_blocker_ids")

    assert_no_difference -> { Task.count } do
      post materialize_children_task_path(brief), params: {
        owner_id: "brief-owner", claim_version: claim.claim_version, children:
      }, headers: @headers, as: :json
    end
    assert_response :success
    assert_equal "unchanged", response.parsed_body.fetch("materialization")
    assert_equal digest, response.parsed_body.fetch("digest")

    get context_task_path(brief), headers: @headers, as: :json
    assert_equal digest, response.parsed_body.fetch("artifacts").find { |entry| entry["step"] == "review" }
      .fetch("graph_digest")
    get artifact_task_path(brief), params: { step: "review" }, headers: @headers
    assert_equal children.map(&:stringify_keys), response.parsed_body.dig("brief_graph", "children")
  end

  test "child graph materialization returns stable errors without partial writes" do
    brief, claim = claimed_brief_at_publish
    children = [ { key: "child", title: "Child", description_markdown: "Work", blocker_keys: [] } ]

    assert_no_difference -> { Task.count } do
      post materialize_children_task_path(brief), params: {
        owner_id: "wrong-owner", claim_version: claim.claim_version, children:
      }, headers: @headers, as: :json
    end
    assert_response :conflict
    assert_equal "conflict", response.parsed_body.fetch("error")

    assert_no_difference [ -> { Task.count }, -> { TaskDependency.count } ] do
      post materialize_children_task_path(brief), params: {
        owner_id: "brief-owner", claim_version: claim.claim_version,
        children: [ children.first.merge(blocker_ids: [ -1 ]) ]
      }, headers: @headers, as: :json
    end
    assert_response :unprocessable_entity
    assert_equal "invalid_graph", response.parsed_body.fetch("error")

    post "/tasks/#{brief.id}/validate-children", params: { children: }, headers: @headers, as: :json
    assert_response :not_found
  end

  test "create and claim rejects incomplete blockers without creating a task" do
    blocker = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    parameters = task_parameters.except(:task_type_id).merge(
      task_type_key: @task_type.key, owner_id: "session", blocker_ids: [ blocker.id ]
    )

    assert_no_difference -> { Task.count } do
      post tasks_create_and_claim_path, params: parameters, headers: @headers, as: :json
    end
    assert_response :conflict
    assert_equal "conflict", response.parsed_body["error"]
  end

  test "filters next claim by type and claims a specific task" do
    other_type = create_task_type(name: "Other", workflow: @workflow)
    other = create_task(project: @project, workflow: @workflow, task_type: other_type)
    requested = create_task(project: @project, workflow: @workflow, task_type: @task_type)

    post tasks_claim_next_path, params: {
      project_id: @project.id, task_type_key: @task_type.key, owner_id: "typed"
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal requested.id, response.parsed_body.dig("task", "id")

    post claim_task_path(other), params: { owner_id: "exact" }, headers: @headers, as: :json
    assert_response :success
    assert_equal other.id, response.parsed_body.dig("task", "id")
  end

  test "rejects exact claims for blocked tasks and owner collisions" do
    blocker = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    blocked = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    TaskDependency.create!(task: blocked, blocker:)

    post claim_task_path(blocked), params: { owner_id: "session" }, headers: @headers, as: :json
    assert_response :conflict

    post claim_task_path(blocker), params: { owner_id: "session" }, headers: @headers, as: :json
    assert_response :success
    available = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    post claim_task_path(available), params: { owner_id: "session" }, headers: @headers, as: :json
    assert_response :conflict
  end

  test "shows an owned task and lists resumable tasks by type without mutation" do
    active = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    post claim_task_path(active), params: { owner_id: "session" }, headers: @headers, as: :json

    get tasks_show_owned_path, params: { project_id: @project.id, owner_id: "session" }, headers: @headers
    assert_response :success
    assert_equal active.id, response.parsed_body.dig("task", "id")

    get tasks_resumable_path, params: { project_id: @project.id, task_type_key: @task_type.key }, headers: @headers
    assert_response :success
    assert_equal [ active.id ], response.parsed_body.map { |item| item.dig("task", "id") }
    assert_equal 1, active.reload.claim_version

    get tasks_show_owned_path, params: { project_id: @project.id, owner_id: "missing" }, headers: @headers
    assert_response :no_content
  end

  test "projects advanced tiers throughout a persisted legacy workflow" do
    definition = valid_workflow_definition.deep_dup
    definition["steps"].each { |step| step.delete("model_tier"); step.delete("execution_mode") }
    workflow = Workflow.new(name: "Legacy", definition_json: definition)
    workflow.save!(validate: false)
    task_type = create_task_type(name: "Legacy", workflow:)
    task = create_task(project: @project, workflow:, task_type:)

    get task_path(task), headers: @headers, as: :json

    assert_response :success
    assert_equal "advanced", response.parsed_body.dig("step", "model_tier")
    assert_equal "subagent", response.parsed_body.dig("step", "execution_mode")
    assert response.parsed_body.dig("workflow", "definition_json", "steps").all? do |step|
      step["model_tier"] == "advanced"
    end
    assert response.parsed_body.dig("workflow", "definition_json", "steps").all? do |step|
      step["execution_mode"] == "subagent"
    end
  end

  test "updates an unclaimed definition and rolls back all changes when a blocker is invalid" do
    original_blocker = create_task(project: @project, workflow: @workflow, task_type: @task_type, title: "Original")
    replacement = create_task(project: @project, workflow: @workflow, task_type: @task_type, title: "Replacement")
    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    TaskDependency.create!(task:, blocker: original_blocker)

    patch task_path(task), params: {
      description_markdown: "Updated",
      parent_id: replacement.id,
      blocker_ids: [ replacement.id ]
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "Updated", task.reload.description_markdown
    assert_equal replacement, task.parent
    assert_equal [ replacement ], task.blockers

    other_project_blocker = create_task
    patch task_path(task), params: {
      description_markdown: "Must roll back",
      blocker_ids: [ other_project_blocker.id ]
    }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
    assert_equal "Updated", task.reload.description_markdown
    assert_equal [ replacement ], task.blockers.reload
  end

  test "claims reports pauses resumes completes and cancels through the API" do
    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)

    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "session-1" },
      headers: @headers, as: :json
    assert_response :success
    assert_equal "active", response.parsed_body.dig("task", "status")
    assert_equal 1, response.parsed_body.dig("task", "claim_version")

    post report_attempt_task_path(task), params: {
      owner_id: "session-1", claim_version: 1, step: "develop", outcome: "question",
      artifact: "# Question", message: "Which option?"
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "needs_human", response.parsed_body.dig("task", "status")
    assert_equal "develop", response.parsed_body.dig("task", "current_step")

    post resume_task_path(task), params: {
      owner_id: "session-2", claim_version: 2, step: "develop", answer: "Option A"
    }, headers: @headers, as: :json
    assert_response :success
    claim_version = response.parsed_body.dig("task", "claim_version")

    get context_task_path(task), headers: @headers, as: :json
    assert_equal "Option A", response.parsed_body.dig("pause", "answer")

    post report_attempt_task_path(task), params: {
      owner_id: "session-2", claim_version:, step: "develop", outcome: "ready", artifact: "# Develop"
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "check", response.parsed_body.dig("step", "id")
    claim_version = response.parsed_body.dig("task", "claim_version")

    get task_path(task), headers: @headers, as: :json
    assert_equal "check", response.parsed_body.dig("task", "current_step")
    assert_equal claim_version, response.parsed_body.dig("task", "claim_version")

    post report_attempt_task_path(task), params: {
      owner_id: "session-2", claim_version:, step: "check", outcome: "passed", artifact: "# Check"
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "completed", task.reload.status

    cancellable = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    post cancel_task_path(cancellable), headers: @headers, as: :json
    assert_response :success
    assert_equal "cancelled", cancellable.reload.status
  end

  test "reports and returns structured required check evidence for built in implementation" do
    BuiltInCatalog.install!
    task_type = TaskType.find_by!(key: "development")
    lifecycle = TaskLifecycle.new
    task = create_task(project: @project, workflow: task_type.workflow, task_type:, current_step: "implement")
    task = lifecycle.claim!(task_id: task.id, owner_id: "checks-owner")

    post report_attempt_task_path(task), params: {
      owner_id: task.owner_id, claim_version: task.claim_version, step: "implement", outcome: "implemented",
      artifact: "# Implementation", required_checks: "failed"
    }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_empty task.reload.accepted_artifacts

    post report_attempt_task_path(task), params: {
      owner_id: task.owner_id, claim_version: task.claim_version, step: "implement", outcome: "implemented",
      artifact: "# Implementation", required_checks: "passed"
    }, headers: @headers, as: :json
    assert_response :success

    get artifact_task_path(task), params: { step: "implement" }, headers: @headers
    assert_response :success
    assert_equal "passed", response.parsed_body.fetch("required_checks")

    get context_task_path(task), headers: @headers, as: :json
    assert_equal "passed", response.parsed_body.fetch("artifacts").first.fetch("required_checks")
  end

  test "returns no content when no task can be claimed" do
    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "session" },
      headers: @headers, as: :json

    assert_response :no_content
    assert_empty response.body
  end

  test "maps not found invalid transitions conflicts and bad types to stable errors" do
    get task_path(-1), headers: @headers, as: :json
    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]

    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "session" },
      headers: @headers, as: :json
    assert_response :success

    post report_attempt_task_path(task), params: {
      owner_id: "session", claim_version: 1, step: "develop", outcome: "unknown", artifact: "# Unknown"
    }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid_transition", response.parsed_body["error"]

    post report_attempt_task_path(task), params: {
      owner_id: "stale", claim_version: 1, step: "develop", outcome: "ready", artifact: "# Stale"
    }, headers: @headers, as: :json
    assert_response :conflict
    assert_equal "conflict", response.parsed_body["error"]

    post resume_task_path(task), params: {
      owner_id: "other", claim_version: 1, step: "develop", takeover_confirmed: "true"
    },
      headers: @headers, as: :json
    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]
  end

  test "returns not found when resuming or cancelling an unknown task" do
    post resume_task_path(-1), params: {
      owner_id: "session", claim_version: 1, step: "develop"
    }, headers: @headers, as: :json
    assert_response :not_found

    post cancel_task_path(-1), headers: @headers, as: :json
    assert_response :not_found
  end

  test "rejects definition edits after a claim" do
    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "session" },
      headers: @headers, as: :json

    patch task_path(task), params: { description_markdown: "Too late" }, headers: @headers, as: :json

    assert_response :conflict
    assert_equal "Description", task.reload.description_markdown
  end

  test "requires typed required task parameters" do
    post tasks_path, params: task_parameters.merge(blocker_ids: "not-an-array"), headers: @headers, as: :json
    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]

    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "" }, headers: @headers, as: :json
    assert_response :bad_request

    post tasks_claim_next_path, params: {
      project_id: @project.id, owner_id: "session", task_type_key: "missing"
    }, headers: @headers, as: :json
    assert_response :not_found

    get tasks_resumable_path, params: { project_id: "not-an-id", task_type_key: @task_type.key }, headers: @headers
    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]
  end

  test "requires authentication on every task route" do
    requests = [
      -> { post tasks_path, params: {}, as: :json },
      -> { post tasks_create_and_claim_path, params: {}, as: :json },
      -> { get task_path(1), as: :json },
      -> { get context_task_path(1), as: :json },
      -> { get artifact_task_path(1), headers: {
        "Authorization" => "Bearer wrong"
      }, as: :json },
      -> { get tasks_show_owned_path, as: :json },
      -> { get tasks_resumable_path, as: :json },
      -> { patch task_path(1), params: {}, as: :json },
      -> { post tasks_claim_next_path, params: {}, as: :json },
      -> { post claim_task_path(1), params: {}, as: :json },
      -> { post resume_task_path(1), params: {}, as: :json },
      -> { post report_attempt_task_path(1), params: {}, as: :json },
      -> { post cancel_task_path(1), params: {}, as: :json },
      -> { post materialize_children_task_path(1), params: {}, as: :json },
      -> { get children_task_path(1), as: :json }
    ]

    requests.each do |request|
      request.call
      assert_response :unauthorized
      assert_equal({ "error" => "unauthorized" }, response.parsed_body)
    end
  end

  test "does not expose PUT as an update alias" do
    put task_path(1), params: {}, headers: @headers, as: :json

    assert_response :not_found
  end

  private

  def task_parameters
    {
      project_id: @project.id,
      task_type_id: @task_type.id,
      title: "API task",
      description_markdown: "Created through the API"
    }
  end

  def claimed_brief_at_publish
    BuiltInCatalog.install!
    brief_type = TaskType.find_by!(key: "brief")
    lifecycle = TaskLifecycle.new
    brief = lifecycle.create!(project: @project, task_type: brief_type, title: "Brief", description_markdown: "Request")
    claim = lifecycle.claim!(task_id: brief.id, owner_id: "brief-owner")
    claim = lifecycle.report_attempt!(task_id: brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      step: "brief", outcome: "specified", artifact: "# Brief")
    claim = lifecycle.report_attempt!(task_id: brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      step: "review", outcome: "approved", artifact: "# Review", brief_graph: { "children" => [
        { "key" => "core", "title" => "Core", "description_markdown" => "Build core", "blocker_keys" => [] },
        { "key" => "surface", "title" => "Surface", "description_markdown" => "Build surface",
          "blocker_keys" => [ "core" ] }
      ] })
    [ brief, claim ]
  end
end
