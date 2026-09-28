require "test_helper"

class ReadinessTest < ActionDispatch::IntegrationTest
  setup { BuiltInCatalog.install! }

  test "liveness and readiness have distinct public meanings" do
    get rails_health_check_path
    assert_response :success

    get readiness_path, as: :json
    assert_response :success
    assert_equal({
      "status" => "ready",
      "version" => Kos::VERSION,
      "source_id" => Rails.application.config.x.kos.source_id
    }, response.parsed_body)
  end

  test "readiness fails generically when the canonical catalog is unavailable while liveness remains up" do
    Workflow.find_by!(key: "development", revision: BuiltInCatalog::REVISION)
      .update_column(:key, "development-unavailable")

    get readiness_path, as: :json, headers: { "X-Request-Id" => "readiness-correlation" }
    assert_response :service_unavailable
    assert_equal "unavailable", response.parsed_body.fetch("status")
    assert_equal Kos::VERSION, response.parsed_body.fetch("version")
    assert_equal Rails.application.config.x.kos.source_id, response.parsed_body.fetch("source_id")
    refute_includes response.body, "development"

    get rails_health_check_path
    assert_response :success
  end

  test "readiness accepts obsolete built-in revisions alongside the current catalog" do
    create_workflow(key: "development", revision: BuiltInCatalog::REVISION - 1,
      definition: valid_workflow_definition, name: "Old development")

    assert ReadinessCheck.call
  end

  test "readiness requires the complete canonical catalog entry" do
    Workflow.find_by!(key: "development", revision: BuiltInCatalog::REVISION)
      .update_column(:name, "Not canonical")

    error = assert_raises(ReadinessCheck::Error) { ReadinessCheck.call }
    assert_equal :catalog, error.component
  end

  test "readiness rejects a database that cannot accept writes" do
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA query_only = ON")

    error = assert_raises(ReadinessCheck::Error) { ReadinessCheck.call }
    assert_equal :database, error.component
  ensure
    connection&.execute("PRAGMA query_only = OFF")
  end
end
