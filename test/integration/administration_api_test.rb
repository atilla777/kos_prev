require "test_helper"

class AdministrationApiTest < ActionDispatch::IntegrationTest
  setup { @headers = { "Authorization" => "Bearer test-api-token" } }

  test "registers and reads projects" do
    post projects_path, params: {
      name: "KOS", remote_url: "https://example.test/test/kos.git", default_branch: "main"
    }, headers: @headers, as: :json
    assert_response :created
    id = response.parsed_body.dig("project", "id")

    get project_path(id), headers: @headers
    assert_response :success
    assert_equal "example.test/test/kos", response.parsed_body.dig("project", "repository_identity")

    get projects_path, params: { repository_identity: "example.test/test/kos" }, headers: @headers
    assert_response :success
    assert_equal id, response.parsed_body.dig("project", "id")
  end

  test "explains how to register an absent project without changing the error discriminator" do
    get projects_path, params: { repository_identity: "github.com/acme/missing" }, headers: @headers

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.fetch("error")
    assert_includes response.parsed_body.fetch("message"), "kos project create"
  end

  test "creates and reads immutable workflow revisions" do
    post workflows_path, params: {
      key: "delivery", name: "Delivery", definition_json: valid_workflow_definition
    }, headers: @headers, as: :json
    assert_response :created
    workflow_id = response.parsed_body.dig("workflow", "id")
    assert_equal 1, response.parsed_body.dig("workflow", "revision")

    get workflow_path(workflow_id), headers: @headers
    assert_response :success
    assert_equal valid_workflow_definition, response.parsed_body.dig("workflow", "definition_json")

    post workflows_path, params: {
      key: "delivery", name: "Delivery v2", definition_json: valid_workflow_definition
    }, headers: @headers, as: :json
    assert_response :created
    assert_equal 2, response.parsed_body.dig("workflow", "revision")

    create_workflow(key: "analysis")
    get workflows_path, headers: @headers
    assert_equal %w[analysis delivery delivery], response.parsed_body.fetch("workflows").pluck("key")
    get workflows_path, params: { key: "delivery" }, headers: @headers
    assert_equal [ 1, 2 ], response.parsed_body.fetch("workflows").pluck("revision")
  end

  test "publishes the authenticated workflow definition schema and valid example" do
    get workflow_schema_path, headers: @headers

    assert_response :success
    assert_equal Kos::WorkflowDefinition.contract, response.parsed_body.fetch("schema")
    example = response.parsed_body.fetch("example")
    assert Workflow.new(key: "schema-example", name: "Schema example", revision: 1,
      definition_json: example).valid?

    get workflow_schema_path
    assert_response :unauthorized
  end

  test "identifies a missing workflow revision without changing the discriminator" do
    get workflow_path(123_456), headers: @headers

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.fetch("error")
    assert_includes response.parsed_body.fetch("message"), "Workflow"
    assert_includes response.parsed_body.fetch("message"), "123456"
  end

  test "rejects oversized API input without persistence" do
    assert_no_difference -> { Project.count } do
      post projects_path, params: {
        name: "x" * (CoordinationLimits::MAX_NAME_BYTES + 1),
        remote_url: "https://example.test/test/large.git", default_branch: "main"
      }, headers: @headers, as: :json
    end
    assert_response :bad_request

    assert_no_difference -> { Workflow.count } do
      post workflows_path, params: {
        key: "large", name: "Large", definition_json: {
          steps: [ { id: "work", name: "Work", instruction: "x" * (CoordinationLimits::MAX_TEXT_BYTES + 1),
            outcomes: { done: { complete_task: true } } } ]
        }
      }, headers: @headers, as: :json
    end
    assert_response :unprocessable_entity
  end

  test "rejects request bodies over 8 MiB before dispatch" do
    prefix = '{"ignored":"'
    suffix = '"}'
    body = prefix + ("x" * (CoordinationLimits::MAX_REQUEST_BODY_BYTES - prefix.bytesize - suffix.bytesize)) + suffix
    post projects_path, params: body, headers: @headers.merge("CONTENT_TYPE" => "application/json")
    assert_response :bad_request

    body << "x"
    assert_no_difference -> { Project.count } do
      post projects_path, params: body, headers: @headers.merge("CONTENT_TYPE" => "application/json")
    end
    assert_response :content_too_large
    assert_equal "request_too_large", response.parsed_body.fetch("error")
  end

  test "requires authentication" do
    get projects_path, params: { repository_identity: "example.test/test/kos" }
    assert_response :unauthorized
    post workflows_path, params: {}, as: :json
    assert_response :unauthorized
  end
end
