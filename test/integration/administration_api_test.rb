require "test_helper"

class AdministrationApiTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-api-token" }
  end

  test "registers projects workflows and task types" do
    post projects_path, params: {
      name: "KOS",
      remote_url: "https://example.test/test/kos.git",
      default_branch: "main"
    }, headers: @headers, as: :json
    assert_response :created
    assert_equal %w[created_at default_branch id name remote_url repository_identity updated_at],
      response.parsed_body.fetch("project").keys.sort
    assert_equal "KOS", response.parsed_body.dig("project", "name")
    assert_equal "example.test/test/kos", response.parsed_body.dig("project", "repository_identity")

    post workflows_path, params: {
      name: "Default",
      definition_json: valid_workflow_definition
    }, headers: @headers, as: :json
    assert_response :created
    workflow_id = response.parsed_body.dig("workflow", "id")
    assert_equal valid_workflow_definition, response.parsed_body.dig("workflow", "definition_json")

    post task_types_path, params: { key: "feature", name: "Feature", workflow_id: }, headers: @headers, as: :json
    assert_response :created
    assert_equal "feature", response.parsed_body.dig("task_type", "key")
    assert_equal workflow_id, response.parsed_body.dig("task_type", "workflow_id")
  end

  test "rejects a new workflow without an explicit model tier" do
    definition = valid_workflow_definition
    definition["steps"][0].delete("model_tier")

    post workflows_path, params: { name: "Missing tier", definition_json: definition }, headers: @headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
  end

  test "rejects a new workflow without an explicit execution mode" do
    definition = valid_workflow_definition
    definition["steps"][0].delete("execution_mode")

    post workflows_path, params: { name: "Missing mode", definition_json: definition }, headers: @headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
  end

  test "rejects a workflow whose reachable steps cannot complete" do
    definition = valid_workflow_definition.deep_dup
    definition["steps"][1]["outcomes"] = { "again" => { "next_step" => "develop" } }

    assert_no_difference -> { Workflow.count } do
      post workflows_path, params: { name: "Closed cycle", definition_json: definition }, headers: @headers, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
    assert_includes response.parsed_body.dig("details", "definition_json"),
      "reachable steps without a path to complete_task: develop, check"
  end

  test "changes a task type workflow without changing existing tasks" do
    original = create_workflow(name: "Original")
    replacement = create_workflow(name: "Replacement")
    task_type = create_task_type(name: "Feature", key: "feature", workflow: original)
    task = create_task(workflow: original, task_type:)

    patch task_type_path(task_type), params: { workflow_id: replacement.id }, headers: @headers, as: :json

    assert_response :success
    assert_equal "feature", response.parsed_body.dig("task_type", "key")
    assert_equal replacement.id, response.parsed_body.dig("task_type", "workflow_id")
    assert_equal original, task.reload.workflow
  end

  test "does not publicly replace reserved task type workflows" do
    BuiltInCatalog.install!
    replacement = create_workflow(name: "Replacement")

    TaskType::RESERVED_KEYS.each do |key|
      task_type = TaskType.find_by!(key:)
      original_id = task_type.workflow_id
      patch task_type_path(task_type), params: { workflow_id: replacement.id }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body["error"]
      assert_equal original_id, task_type.reload.workflow_id
    end
  end

  test "rejects duplicate and reserved task type keys" do
    workflow = create_workflow
    create_task_type(key: "feature", workflow:)

    [ "feature", "brief", "development", "fix" ].each do |key|
      post task_types_path, params: { key:, name: key.titleize, workflow_id: workflow.id }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body["error"]
      assert response.parsed_body.fetch("details").key?("key")
    end
  end

  test "returns stable errors for malformed and invalid administration requests" do
    post projects_path, params: { name: "Missing fields" }, headers: @headers, as: :json
    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]

    post workflows_path, params: { name: "Invalid", definition_json: { steps: [] } }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
    assert response.parsed_body.fetch("details").key?("definition_json")

    post task_types_path, params: { key: "missing", name: "Missing workflow", workflow_id: -1 }, headers: @headers,
      as: :json
    assert_response :not_found
    assert_equal({ "error" => "not_found" }, response.parsed_body)
  end

  test "looks up an exact repository identity and updates a project in place" do
    project = create_project(remote_url: "https://github.com/acme/kos.git")
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    task = create_task(project:, workflow:, task_type:)
    task.update_columns(accepted_artifacts: { "develop" => { "outcome" => "ready" } },
      pause_message: "preserve", pause_step: "develop", pause_claim_version: 2,
      human_answer: "answer", human_answer_step: "develop", human_answer_claim_version: 1)

    get projects_path, params: { repository_identity: "github.com/acme/kos" }, headers: @headers
    assert_response :success
    assert_equal({
      "id" => project.id,
      "name" => project.name,
      "repository_identity" => "github.com/acme/kos",
      "remote_url" => "https://github.com/acme/kos.git",
      "default_branch" => "main",
      "created_at" => project.created_at.as_json,
      "updated_at" => project.updated_at.as_json
    }, response.parsed_body.fetch("project"))

    get projects_path, params: { repository_identity: "GitHub.com/acme/kos" }, headers: @headers
    assert_response :not_found
    assert_equal({ "error" => "not_found" }, response.parsed_body)

    patch project_path(project), params: {
      name: "Transferred KOS",
      remote_url: "git@github.com:new-owner/kos.git",
      repository_identity: "github.com/new-owner/kos",
      default_branch: "trunk"
    }, headers: @headers, as: :json

    assert_response :success
    assert_equal project.id, response.parsed_body.dig("project", "id")
    assert_equal "github.com/new-owner/kos", response.parsed_body.dig("project", "repository_identity")
    assert_equal [ project.id, workflow.id, task_type.id ],
      [ task.reload.project_id, task.workflow_id, task.task_type_id ]
    assert_equal({ "develop" => { "outcome" => "ready" } }, task.accepted_artifacts)
    assert_equal [ "preserve", "develop", 2, "answer", "develop", 1 ],
      task.values_at(:pause_message, :pause_step, :pause_claim_version, :human_answer, :human_answer_step,
        :human_answer_claim_version)
  end

  test "returns stable project lookup update collision remote and branch errors" do
    project = create_project(remote_url: "https://github.com/acme/kos.git")
    other = create_project(remote_url: "https://github.com/acme/other.git")

    get projects_path, params: { repository_identity: "github.com/acme/missing" }, headers: @headers
    assert_response :not_found
    assert_equal({ "error" => "not_found" }, response.parsed_body)

    post projects_path, params: {
      name: "Duplicate", remote_url: "git@github.com:acme/kos.git", default_branch: "main"
    }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
    assert response.parsed_body.fetch("details").key?("repository_identity")

    post projects_path, params: {
      name: "Unsafe", remote_url: "git@github.com:/acme/unsafe.git", default_branch: "main"
    }, headers: @headers, as: :json
    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]

    [ "bad branch", "topic/" ].each do |branch|
      patch project_path(project), params: { default_branch: branch }, headers: @headers, as: :json
      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body["error"]
      assert response.parsed_body.fetch("details").key?("default_branch")
      assert_equal "main", project.reload.default_branch
    end

    patch project_path(project), params: {
      remote_url: other.remote_url, repository_identity: other.repository_identity
    }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
    assert_equal "github.com/acme/kos", project.reload.repository_identity

    patch project_path(project), params: {}, headers: @headers, as: :json
    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]
  end

  test "returns bad request for malformed JSON" do
    post projects_path, params: "{", headers: @headers.merge("Content-Type" => "application/json")

    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]
  end

  test "requires authentication on every administration route" do
    requests = [
      -> { post projects_path, params: {}, as: :json },
      -> { get projects_path, params: { repository_identity: "example.test/test/kos" } },
      -> { patch project_path(1), params: {}, as: :json },
      -> { post workflows_path, params: {}, as: :json },
      -> { post task_types_path, params: {}, as: :json },
      -> { patch task_type_path(1), params: {}, as: :json }
    ]

    requests.each do |request|
      request.call
      assert_response :unauthorized
      assert_equal({ "error" => "unauthorized" }, response.parsed_body)
    end
  end

  test "does not expose PUT as an update alias" do
    put project_path(1), params: {}, headers: @headers, as: :json
    assert_response :not_found

    put task_type_path(1), params: {}, headers: @headers, as: :json

    assert_response :not_found
  end
end
