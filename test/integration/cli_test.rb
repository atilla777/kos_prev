require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "tempfile"

class CliTest < ActiveSupport::TestCase
  test "advertises only the focused command surface" do
    output, error, status = run_cli("--help", environment: {})

    assert_predicate status, :success?
    assert_empty error
    assert_match(/^\s*health\s*$/, output)
    assert_match(/^\s*claim-id\s*$/, output)
    assert_match(/^\s*project create \| show \| update\s*$/, output)
    assert_match(/^\s*workflow create\s*$/, output)
    assert_match(/^\s*plan put \| show\s*$/, output)
    assert_match(/^\s*task ready \| show \| context \| result \| claim \| takeover \| report \| answer\s*$/, output)
    %w[session-id task-type create-or-get resume lease artifact report-attempt materialize children graph].each do |removed|
      refute_match(/\b#{Regexp.escape(removed)}\b/, output)
    end

    {
      %w[workflow create] => %w[--key --name --definition-file],
      %w[plan put] => %w[--project-id --definition-file],
      %w[plan show] => %w[--project-id --key],
      %w[task ready] => %w[--project-id],
      %w[task result] => %w[--step],
      %w[task claim] => %w[--claim-id --version],
      %w[task takeover] => %w[--claim-id --version --step],
      %w[task report] => %w[--claim-id --version --step --outcome --result-file --message],
      %w[task answer] => %w[--version --step --answer-file]
    }.each do |command, options|
      command_output, command_error, command_status = run_cli(*command, "--help", environment: {})
      assert_predicate command_status, :success?, command.join(" ")
      assert_match(/Usage: kos #{Regexp.escape(command.join(" "))}/, command_output)
      options.each { |option| assert_includes command_output, option }
      assert_empty command_error
    end
  end

  test "generates fresh claim ids without API configuration" do
    ids = 2.times.map do
      output, error, status = run_cli("claim-id", environment: { "KOS_API_URL" => "invalid" })
      assert_predicate status, :success?
      assert_empty error
      assert_match(/\Akos-claim-[0-9a-f]{32}\n\z/, output)
      output
    end
    assert_equal 2, ids.uniq.length

    _output, error, status = run_cli("claim-id", "extra", environment: {})
    assert_equal 2, status.exitstatus
    assert_equal "usage_error", JSON.parse(error).fetch("error")
  end

  test "checks public health without a token and preserves its body" do
    output, error, status, request = run_cli_with_server("health", response_body: "healthy", token: nil)

    assert_predicate status, :success?
    assert_equal "healthy", output
    assert_empty error
    assert_equal [ "GET", "/api/up" ], request.values_at(:method, :path)
    refute request.fetch(:headers).key?("authorization")
  end

  test "maps every server operation with separate arguments and file input" do
    Tempfile.create([ "definition", ".json" ]) do |definition|
      definition.write(JSON.generate(steps: [ { id: "work" } ]))
      definition.flush
      Tempfile.create([ "plan", ".json" ]) do |plan|
        plan.write(JSON.generate(key: "goal", title: "Goal", tasks: [ { key: "one", title: "One",
          description_markdown: "Do it", workflow_key: "delivery", blocker_keys: [] } ]))
        plan.flush
        Tempfile.create([ "result", ".md" ]) do |result|
          result.write("# Result\n")
          result.flush

          cases = [
            [ [ "project", "create", "--name", "KOS", "--remote-url", "https://example.test/acme/kos.git",
              "--default-branch", "main", "--repository-identity", "example.test/acme/kos" ],
              "POST", "/projects", { "name" => "KOS", "remote_url" => "https://example.test/acme/kos.git",
                "default_branch" => "main", "repository_identity" => "example.test/acme/kos" } ],
            [ [ "project", "show", "--repository-identity", "example.test/acme/kos" ],
              "GET", "/projects?repository_identity=example.test%2Facme%2Fkos", nil ],
            [ [ "project", "update", "7", "--name", "Renamed" ], "PATCH", "/projects/7", { "name" => "Renamed" } ],
            [ [ "workflow", "create", "--key", "delivery", "--name", "Delivery", "--definition-file",
              definition.path ], "POST", "/workflows", { "key" => "delivery", "name" => "Delivery",
                "definition_json" => { "steps" => [ { "id" => "work" } ] } } ],
            [ [ "plan", "put", "--project-id", "7", "--definition-file", plan.path ],
              "PUT", "/projects/7/plan", { "key" => "goal", "title" => "Goal", "tasks" => [ {
                "key" => "one", "title" => "One", "description_markdown" => "Do it",
                "workflow_key" => "delivery", "blocker_keys" => []
              } ] } ],
            [ [ "plan", "show", "--project-id", "7", "--key", "goal" ],
              "GET", "/projects/7/plan?key=goal", nil ],
            [ [ "task", "ready", "--project-id", "7" ], "GET", "/tasks/ready?project_id=7", nil ],
            [ [ "task", "show", "9" ], "GET", "/tasks/9", nil ],
            [ [ "task", "context", "9" ], "GET", "/tasks/9/context", nil ],
            [ [ "task", "result", "9", "--step", "work" ], "GET", "/tasks/9/result?step=work", nil ],
            [ [ "task", "claim", "9", "--claim-id", "claim-a", "--version", "0" ], "POST", "/tasks/9/claim",
              { "claim_id" => "claim-a", "version" => 0 } ],
            [ [ "task", "takeover", "9", "--claim-id", "claim-b", "--version", "4", "--step", "work" ],
              "POST", "/tasks/9/takeover", { "claim_id" => "claim-b", "version" => 4, "step" => "work" } ],
            [ [ "task", "report", "9", "--claim-id", "claim-b", "--version", "5", "--step", "work",
              "--outcome", "done", "--result-file", result.path, "--message", "evidence" ],
              "POST", "/tasks/9/report", { "claim_id" => "claim-b", "version" => 5, "step" => "work",
                "outcome" => "done", "message" => "evidence", "result" => "# Result\n" } ],
            [ [ "task", "answer", "9", "--version", "6", "--step", "work", "--answer-file", "-" ],
              "POST", "/tasks/9/answer", { "version" => 6, "step" => "work", "answer" => "Proceed\n" }, "Proceed\n" ]
          ]

          cases.each do |arguments, expected_method, expected_path, expected_body, stdin_data|
            output, error, status, request = run_cli_with_server(*arguments, stdin_data: stdin_data.to_s)
            assert_predicate status, :success?, arguments.join(" ")
            assert_equal "{\"ok\":true}", output
            assert_empty error
            assert_equal expected_method, request.fetch(:method)
            assert_equal "/api#{expected_path}", request.fetch(:path)
            assert_equal "Bearer test-secret", request.fetch(:headers).fetch("authorization")
            expected_body.nil? ? assert_nil(request.fetch(:body)) : assert_equal(expected_body, request.fetch(:body))
          end
        end
      end
    end
  end

  test "reads JSON and results from stdin and validates local input" do
    output, error, status, request = run_cli_with_server("workflow", "create", "--key", "x", "--name", "X",
      "--definition-file", "-", stdin_data: "{\"steps\":[]}")
    assert_predicate status, :success?
    assert_equal({ "steps" => [] }, request.dig(:body, "definition_json"))
    assert_equal "{\"ok\":true}", output
    assert_empty error

    _output, error, status = run_cli("plan", "put", "--project-id", "1", "--definition-file", "-",
      environment: { "KOS_API_TOKEN" => "secret" }, stdin_data: "[]")
    assert_equal 2, status.exitstatus
    assert_equal "local_input_error", JSON.parse(error).fetch("error")

    Tempfile.create("invalid-result") do |file|
      file.binmode
      file.write("\xFF".b)
      file.flush
      _output, error, status = run_cli("task", "report", "1", "--claim-id", "c", "--version", "1",
        "--step", "work", "--outcome", "done", "--result-file", file.path,
        environment: { "KOS_API_TOKEN" => "secret" })
      assert_equal 2, status.exitstatus
      assert_equal "local_input_error", JSON.parse(error).fetch("error")
    end
  end

  test "preserves server failures and reports local and transport failures separately" do
    body = "{\"error\":\"conflict\",\"message\":\"stale claim\"}"
    output, error, status, = run_cli_with_server("task", "show", "9", response_status: 409, response_body: body)
    assert_equal 1, status.exitstatus
    assert_equal body, output
    assert_empty error

    _output, error, status = run_cli("task", "show", "9", environment: {})
    assert_equal 2, status.exitstatus
    assert_equal "configuration_error", JSON.parse(error).fetch("error")

    unavailable = TCPServer.new("127.0.0.1", 0)
    port = unavailable.local_address.ip_port
    unavailable.close
    _output, error, status = run_cli("task", "show", "9", environment: {
      "KOS_API_URL" => "http://127.0.0.1:#{port}", "KOS_API_TOKEN" => "hidden"
    })
    assert_equal 3, status.exitstatus
    assert_equal "transport_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "hidden"
  end

  private

  def run_cli_with_server(*arguments, response_status: 200, response_body: "{\"ok\":true}", stdin_data: "", token: "test-secret")
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
      requests << { method: request_line.split.fetch(0), path: request_line.split.fetch(1), headers:,
                    body: raw_body.empty? ? nil : JSON.parse(raw_body) }
      reason = { 200 => "OK", 409 => "Conflict" }.fetch(response_status)
      socket.write("HTTP/1.1 #{response_status} #{reason}\r\nContent-Type: application/json\r\n" \
        "Content-Length: #{response_body.bytesize}\r\nConnection: close\r\n\r\n#{response_body}")
      socket.close
    ensure
      server.close
    end
    thread.report_on_exception = false

    environment = { "KOS_API_URL" => "http://127.0.0.1:#{server.local_address.ip_port}/api/" }
    environment["KOS_API_TOKEN"] = token if token
    output, error, status = run_cli(*arguments, environment:, stdin_data:)
    unless thread.join(2)
      server.close
      thread.kill
      flunk("CLI did not send a request: #{arguments.join(" ")} (stderr: #{error.inspect})")
    end
    [ output, error, status, requests.pop ]
  end

  def run_cli(*arguments, environment:, stdin_data: "")
    isolated = { "KOS_API_TOKEN" => nil, "KOS_API_URL" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil }.merge(environment)
    Open3.capture3(isolated, RbConfig.ruby, "--disable-gems", Rails.root.join("bin/kos").to_s, *arguments,
      stdin_data:)
  end
end
