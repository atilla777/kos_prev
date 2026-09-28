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
  end

  test "requires authentication" do
    get projects_path, params: { repository_identity: "example.test/test/kos" }
    assert_response :unauthorized
    post workflows_path, params: {}, as: :json
    assert_response :unauthorized
  end
end
