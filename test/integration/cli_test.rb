require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "tempfile"

class CliTest < ActiveSupport::TestCase
  test "prints top-level and command help without configuration" do
    output, error, status = run_cli("--help", environment: {})

    assert_predicate status, :success?
    assert_includes output, "Usage: kos <resource> <action> [options]"
    assert_empty error

    output, error, status = run_cli("task", "report-attempt", "--help", environment: {})

    assert_predicate status, :success?
    assert_includes output, "--claim-version VERSION"
    assert_includes output, "--artifact-file FILE"
    assert_empty error
  end

  test "prints its version without configuration" do
    output, error, status = run_cli("--version", environment: {})

    assert_predicate status, :success?
    assert_equal "kos #{Kos::VERSION}\n", output
    assert_empty error
  end

  test "requires a task type key" do
    _output, error, status = run_cli("task-type", "create", "--name", "Feature", "--workflow-id", "4",
      environment: {})

    assert_equal 2, status.exitstatus
    assert_equal "usage_error", JSON.parse(error).fetch("error")
    assert_includes JSON.parse(error).fetch("message"), "--key"
  end

  test "maps every API operation to its HTTP request" do
    Tempfile.create([ "workflow", ".json" ]) do |workflow_file|
      workflow_file.write(JSON.generate(steps: [ { id: "develop" } ]))
      workflow_file.flush

      Tempfile.create([ "description", ".md" ]) do |description_file|
        description_file.write("# Task\n\nMultiline description.\n")
        description_file.flush

        Tempfile.create([ "children", ".json" ]) do |children_file|
          children_file.write(JSON.generate(children: [ {
            key: "child", title: "Child", description_markdown: "Work", blocker_keys: []
          } ]))
          children_file.flush

          cases = [
          [ [ "project", "create", "--name", "KOS", "--remote-url", "git@example.test:test/kos.git",
            "--default-branch", "main", "--repository-identity", "example.test/test/kos" ], "POST", "/projects",
            { "name" => "KOS", "remote_url" => "git@example.test:test/kos.git", "default_branch" => "main",
              "repository_identity" => "example.test/test/kos" } ],
          [ [ "project", "show", "--repository-identity", "example.test/test/kos" ],
            "GET", "/projects?repository_identity=example.test%2Ftest%2Fkos", nil ],
          [ [ "project", "update", "7", "--name", "Renamed", "--remote-url",
            "https://example.test/new/kos.git", "--repository-identity", "example.test/new/kos",
            "--default-branch", "trunk" ], "PATCH", "/projects/7",
            { "name" => "Renamed", "remote_url" => "https://example.test/new/kos.git",
              "repository_identity" => "example.test/new/kos", "default_branch" => "trunk" } ],
          [ [ "workflow", "create", "--name", "Default", "--definition-file", workflow_file.path ],
            "POST", "/workflows", { "name" => "Default", "definition_json" => { "steps" => [ { "id" => "develop" } ] } } ],
          [ [ "task-type", "create", "--key", "feature", "--name", "Feature", "--workflow-id", "4" ],
            "POST", "/task_types", { "key" => "feature", "name" => "Feature", "workflow_id" => 4 } ],
          [ [ "task-type", "update", "7", "--workflow-id", "5" ],
            "PATCH", "/task_types/7", { "workflow_id" => 5 } ],
          [ [ "task", "create", "--project-id", "1", "--task-type-id", "2", "--title", "CLI task",
            "--description-file", description_file.path, "--parent-id", "3", "--blocker-id", "4", "--blocker-id", "5" ],
            "POST", "/tasks", { "project_id" => 1, "task_type_id" => 2, "title" => "CLI task",
              "description_markdown" => "# Task\n\nMultiline description.\n", "parent_id" => 3, "blocker_ids" => [ 4, 5 ] } ],
          [ [ "task", "create", "--project-id", "1", "--task-type-key", "development", "--title", "Typed",
            "--description-file", description_file.path ],
            "POST", "/tasks", { "project_id" => 1, "task_type_key" => "development", "title" => "Typed",
              "description_markdown" => "# Task\n\nMultiline description.\n", "blocker_ids" => [] } ],
          [ [ "task", "create-and-claim", "--project-id", "1", "--task-type-key", "fix", "--title", "Fix",
            "--description-file", description_file.path, "--owner-id", "intent-owner", "--creation-key",
            "request:fix:sha256:abc" ],
            "POST", "/tasks/create-and-claim", { "project_id" => 1, "task_type_key" => "fix", "title" => "Fix",
              "description_markdown" => "# Task\n\nMultiline description.\n", "owner_id" => "intent-owner",
              "creation_key" => "request:fix:sha256:abc", "blocker_ids" => [] } ],
          [ [ "task", "update", "9", "--description-file", "-", "--clear-parent", "--clear-blockers" ],
            "PATCH", "/tasks/9", { "description_markdown" => "Updated through STDIN\n", "parent_id" => nil, "blocker_ids" => [] },
            "Updated through STDIN\n" ],
          [ [ "task", "show", "9" ], "GET", "/tasks/9", nil ],
          [ [ "task", "context", "9" ], "GET", "/tasks/9/context", nil ],
          [ [ "task", "artifact", "9", "--step", "develop" ],
            "GET", "/tasks/9/artifact?step=develop", nil ],
          [ [ "task", "show-owned", "--project-id", "1", "--owner-id", "session-1" ],
            "GET", "/tasks/show-owned?project_id=1&owner_id=session-1", nil ],
          [ [ "task", "claim-next", "--project-id", "1", "--task-type-key", "development", "--owner-id", "session-1" ],
            "POST", "/tasks/claim-next", { "project_id" => 1, "task_type_key" => "development",
              "owner_id" => "session-1" } ],
          [ [ "task", "claim", "9", "--owner-id", "session-1" ],
            "POST", "/tasks/9/claim", { "owner_id" => "session-1" } ],
          [ [ "task", "resumable", "--project-id", "1", "--task-type-key", "fix" ],
            "GET", "/tasks/resumable?project_id=1&task_type_key=fix", nil ],
          [ [ "task", "resume", "9", "--owner-id", "session-2", "--claim-version", "5", "--step", "develop",
            "--answer-file", description_file.path ],
            "POST", "/tasks/9/resume", { "owner_id" => "session-2", "claim_version" => 5, "step" => "develop",
              "answer" => "# Task\n\nMultiline description.\n", "takeover_confirmed" => false } ],
          [ [ "task", "report-attempt", "9", "--owner-id", "session-2", "--claim-version", "6",
            "--step", "develop", "--outcome", "ready", "--artifact-file", description_file.path ],
            "POST", "/tasks/9/report-attempt", { "owner_id" => "session-2", "claim_version" => 6,
              "step" => "develop", "outcome" => "ready", "artifact" => "# Task\n\nMultiline description.\n" } ],
            [ [ "task", "cancel", "9" ], "POST", "/tasks/9/cancel", {} ],
            [ [ "task", "validate-children", "9", "--definition-file", children_file.path ],
              "POST", "/tasks/9/validate-children", { "children" => [ {
                "key" => "child", "title" => "Child", "description_markdown" => "Work", "blocker_keys" => []
              } ] } ],
            [ [ "task", "materialize-children", "9", "--definition-file", children_file.path,
              "--owner-id", "brief-owner", "--claim-version", "3", "--expected-digest", "sha256:abc" ],
              "POST", "/tasks/9/materialize-children", { "owner_id" => "brief-owner", "claim_version" => 3,
                "expected_digest" => "sha256:abc", "children" => [ {
                  "key" => "child", "title" => "Child", "description_markdown" => "Work", "blocker_keys" => []
                } ] } ],
            [ [ "task", "children", "9" ], "GET", "/tasks/9/children", nil ]
          ]

          cases.each do |arguments, expected_method, expected_path, expected_payload, stdin_data|
            output, error, status, request = run_cli_with_server(*arguments, stdin_data: stdin_data.to_s)

            assert_predicate status, :success?, arguments.join(" ")
            assert_equal "{\"task\":{\"id\":9}}", output
            assert_empty error
            assert_equal expected_method, request.fetch(:method)
            assert_equal "/api#{expected_path}", request.fetch(:path)
            assert_equal "Bearer test-secret", request.fetch(:headers).fetch("authorization")
            expected_payload.nil? ? assert_nil(request.fetch(:body)) : assert_equal(expected_payload, request.fetch(:body))
          end
        end
      end
    end
  end

  test "requires exactly one task type selector for creation" do
    Tempfile.create([ "description", ".md" ]) do |description_file|
      description_file.write("Description")
      description_file.flush
      base = [ "task", "create", "--project-id", "1", "--title", "Task", "--description-file", description_file.path ]

      _output, error, status = run_cli(*base, environment: {})
      assert_equal 2, status.exitstatus
      assert_includes JSON.parse(error).fetch("message"), "exactly one"

      _output, error, status = run_cli(*base, "--task-type-id", "2", "--task-type-key", "development",
        environment: {})
      assert_equal 2, status.exitstatus
      assert_includes JSON.parse(error).fetch("message"), "exactly one"
    end
  end

  test "strictly validates project command arguments" do
    cases = [
      [ "project", "show" ],
      [ "project", "update", "not-an-id", "--name", "KOS" ],
      [ "project", "update", "7" ],
      [ "project", "show", "--repository-identity", "example.test/acme/kos", "extra" ]
    ]

    cases.each do |arguments|
      _output, error, status = run_cli(*arguments, environment: {})
      assert_equal 2, status.exitstatus, arguments.join(" ")
      assert_equal "usage_error", JSON.parse(error).fetch("error")
    end
  end

  test "treats no content as an empty successful response" do
    output, error, status, = run_cli_with_server("task", "claim-next", "--project-id", "1", "--owner-id", "session",
      response_status: 204, response_body: "")

    assert_predicate status, :success?
    assert_empty output
    assert_empty error
  end

  test "preserves server error JSON and returns failure" do
    response_body = "{\"error\":\"conflict\",\"message\":\"stale owner\"}"
    output, error, status, = run_cli_with_server("task", "show", "9", response_status: 409,
      response_body:)

    assert_equal 1, status.exitstatus
    assert_equal response_body, output
    assert_empty error
  end

  test "reports configuration usage local input and transport errors as JSON without secrets" do
    _output, error, status = run_cli("task", "show", "1", environment: {})
    assert_equal 2, status.exitstatus
    assert_equal "configuration_error", JSON.parse(error).fetch("error")

    _output, error, status = run_cli("task", "create", "--project-id", "not-an-id",
      environment: { "KOS_API_TOKEN" => "hidden-secret" })
    assert_equal 2, status.exitstatus
    assert_equal "usage_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "hidden-secret"

    Tempfile.create([ "invalid-workflow", ".json" ]) do |file|
      file.write("{")
      file.flush
      _output, error, status = run_cli("workflow", "create", "--name", "Invalid", "--definition-file", file.path,
        environment: { "KOS_API_TOKEN" => "hidden-secret" })
      assert_equal 2, status.exitstatus
      assert_equal "local_input_error", JSON.parse(error).fetch("error")
      assert_not_includes error, "hidden-secret"
    end

    unavailable_server = TCPServer.new("127.0.0.1", 0)
    port = unavailable_server.local_address.ip_port
    unavailable_server.close
    _output, error, status = run_cli("task", "show", "1", environment: {
      "KOS_API_URL" => "http://127.0.0.1:#{port}", "KOS_API_TOKEN" => "hidden-secret"
    })
    assert_equal 3, status.exitstatus
    assert_equal "transport_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "hidden-secret"
  end

  test "normalizes UTF-8 input and rejects invalid bytes without a stack trace" do
    output, error, status, request = run_cli_with_server("task", "update", "9", "--description-file", "-",
      stdin_data: "Привет\n", cli_environment: { "LANG" => "C", "LC_ALL" => "C" })

    assert_predicate status, :success?
    assert_equal "Привет\n", request.dig(:body, "description_markdown")
    assert_equal "{\"task\":{\"id\":9}}", output
    assert_empty error

    Tempfile.create("invalid-markdown") do |file|
      file.binmode
      file.write("\xFF".b)
      file.flush
      _output, error, status = run_cli("task", "update", "9", "--description-file", file.path,
        environment: { "KOS_API_TOKEN" => "test-secret" })

      assert_equal 2, status.exitstatus
      assert_equal "local_input_error", JSON.parse(error).fetch("error")
      assert_not_includes error, "cli.rb:"
    end

    _output, error, status = run_cli("task", "show", "9", environment: { "KOS_API_TOKEN" => "\xFF".b })
    assert_equal 2, status.exitstatus
    assert_equal "configuration_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "cli.rb:"

    _output, error, status = run_cli("task", "show", "9", "--\xFF".b,
      environment: { "KOS_API_TOKEN" => "test-secret" })
    assert_equal 2, status.exitstatus
    assert_equal "usage_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "cli.rb:"

    _output, error, status = run_cli("task", "update", "9", "--description-file", "/tmp/\xFF".b,
      environment: { "KOS_API_TOKEN" => "test-secret" })
    assert_equal 2, status.exitstatus
    assert_equal "usage_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "cli.rb:"
  end

  test "reads report artifacts from stdin and rejects empty or oversized artifacts locally" do
    arguments = [ "task", "report-attempt", "9", "--owner-id", "session", "--claim-version", "1",
      "--step", "develop", "--outcome", "ready", "--artifact-file", "-" ]
    output, error, status, request = run_cli_with_server(*arguments, stdin_data: "# Artifact\n")

    assert_predicate status, :success?
    assert_equal "# Artifact\n", request.dig(:body, "artifact")
    assert_equal "{\"task\":{\"id\":9}}", output
    assert_empty error

    [ "", "x" * (1024 * 1024 + 1) ].each do |artifact|
      _output, local_error, local_status = run_cli(*arguments,
        environment: { "KOS_API_TOKEN" => "test-secret" }, stdin_data: artifact)
      assert_equal 2, local_status.exitstatus
      assert_equal "local_input_error", JSON.parse(local_error).fetch("error")
    end
  end

  private

  def run_cli_with_server(*arguments, response_status: 200, response_body: "{\"task\":{\"id\":9}}", stdin_data: "",
    cli_environment: {})
    server = TCPServer.new("127.0.0.1", 0)
    requests = Queue.new
    thread = Thread.new do
      socket = server.accept
      request_line = socket.gets
      headers = {}
      while (line = socket.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
      raw_body = socket.read(headers.fetch("content-length", "0").to_i)
      requests << {
        method: request_line.split.fetch(0),
        path: request_line.split.fetch(1),
        headers:,
        body: raw_body.empty? ? nil : JSON.parse(raw_body)
      }
      reason = { 200 => "OK", 204 => "No Content", 409 => "Conflict" }.fetch(response_status)
      socket.write("HTTP/1.1 #{response_status} #{reason}\r\nContent-Type: application/json\r\n" \
        "Content-Length: #{response_body.bytesize}\r\nConnection: close\r\n\r\n#{response_body}")
      socket.close
    ensure
      server.close
    end
    thread.report_on_exception = false

    environment = cli_environment.merge(
      "KOS_API_URL" => "http://127.0.0.1:#{server.local_address.ip_port}/api/",
      "KOS_API_TOKEN" => "test-secret"
    )
    output, error, status = run_cli(*arguments, environment:, stdin_data:)
    unless thread.join(2)
      server.close
      thread.kill
      flunk("CLI did not send a request: #{arguments.join(" ")} (stderr: #{error.inspect})")
    end
    [ output, error, status, requests.pop ]
  end

  def run_cli(*arguments, environment:, stdin_data: "")
    isolated_environment = {
      "KOS_API_TOKEN" => nil, "KOS_API_URL" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil
    }.merge(environment)
    Open3.capture3(isolated_environment, RbConfig.ruby, "--disable-gems", Rails.root.join("bin/kos").to_s, *arguments,
      stdin_data:)
  end
end
