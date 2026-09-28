require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "tempfile"
require "kos/open_code_installation"

class CliTest < ActiveSupport::TestCase
  test "advertises only the focused command surface" do
    output, error, status = run_cli("--help", environment: {})

    assert_predicate status, :success?
    assert_empty error
    assert_match(/^\s*health\s*$/, output)
    assert_match(/^\s*claim-id\s*$/, output)
    assert_match(/^\s*installation check\s*$/, output)
    assert_match(/^\s*project create \| show \| resolve \| update\s*$/, output)
    assert_match(/^\s*status\s*$/, output)
    assert_match(/^\s*workflow create \| list \| show \| schema\s*$/, output)
    assert_match(/^\s*plan put \| list \| show \| abandon\s*$/, output)
    assert_match(/^\s*task list \| ready \| show \| context \| result \| claim \| takeover \| report \| answer\s*$/, output)
    %w[session-id task-type create-or-get resume lease artifact report-attempt materialize children graph].each do |removed|
      refute_match(/\b#{Regexp.escape(removed)}\b/, output)
    end

    {
      %w[installation check] => %w[--manifest],
      %w[project create] => %w[--name --remote-url --default-branch],
      %w[project show] => %w[--repository-identity],
      %w[project resolve] => %w[--remote],
      %w[project update] => [],
      %w[status] => %w[--remote],
      %w[workflow create] => %w[--key --name --definition-file],
      %w[workflow list] => %w[--key],
      %w[workflow show] => [],
      %w[workflow schema] => [],
      %w[plan put] => %w[--project-id --definition-file],
      %w[plan list] => %w[--project-id --include-completed],
      %w[plan show] => %w[--project-id --key],
      %w[plan abandon] => %w[--project-id --key --version],
      %w[task list] => %w[--project-id --include-completed],
      %w[task ready] => %w[--project-id],
      %w[task show] => [],
      %w[task context] => [],
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

    plan_list_help, = run_cli("plan", "list", "--help", environment: {})
    assert_includes plan_list_help, "task_plans fields: id, project_id, key, title, status, version"
    plan_put_help, = run_cli("plan", "put", "--help", environment: {})
    %w[description_markdown workflow_key blocker_keys].each do |field|
      assert_includes plan_put_help, field
    end
    task_list_help, = run_cli("task", "list", "--help", environment: {})
    %w[workflow_id workflow_key workflow_revision claim_id version pause_kind pause_message pause_step answer blocker_ids].each do |field|
      assert_includes task_list_help, field
    end
    workflow_help, = run_cli("workflow", "create", "--help", environment: {})
    [ "containing exactly steps", "id, name, instruction, outcomes", "nonblank valid UTF-8", "next_step", "needs_human", "blocked",
      "complete_task", "Complete valid example", "Perform the task description" ].each do |detail|
      assert_includes workflow_help, detail
    end
    task_show_help, = run_cli("task", "show", "--help", environment: {})
    %w[workflow_id workflow_key workflow_revision current_step claim_id blocker_ids].each do |field|
      assert_includes task_show_help, field
    end
    project_help, = run_cli("project", "create", "--help", environment: {})
    %w[repository_identity created_at updated_at].each { |field| assert_includes project_help, field }
    plan_help, = run_cli("plan", "show", "--help", environment: {})
    %w[task_plan description_markdown current_step blocker_keys].each { |field| assert_includes plan_help, field }
    context_help, = run_cli("task", "context", "--help", environment: {})
    %w[task_plan project workflow instruction allowed_outcomes results pause].each do |field|
      assert_includes context_help, field
    end
    status_help, = run_cli("status", "--help", environment: {})
    %w[project task_plans tasks observational].each { |detail| assert_includes status_help, detail }
    assert Workflow.new(key: "help-example", name: "Help example", revision: 1,
      definition_json: Kos::WorkflowDefinition.example).valid?
  end

  test "resolves an explicitly selected remote and requests recovery status" do
    {
      "https://Example.Test/acme/widget.git" => "example.test/acme/widget",
      "ssh://git@example.test/acme/widget.git" => "example.test/acme/widget",
      "git@example.test:acme/Widget.git" => "example.test/acme/Widget"
    }.each do |remote_url, identity|
      with_git_checkout(remote_url) do |directory, git_environment|
        output, error, status, request = run_cli_with_server("status", "--remote", "upstream",
          environment: git_environment, chdir: directory)

        assert_predicate status, :success?, remote_url
        assert_equal "{\"ok\":true}", output
        assert_empty error
        assert_equal [ "GET", "/api/status?repository_identity=#{URI.encode_www_form_component(identity)}" ],
          request.values_at(:method, :path)
      end
    end

    with_git_checkout("https://example.test/acme/widget.git") do |directory, git_environment|
      _output, error, status, request = run_cli_with_server("project", "resolve", "--remote", "upstream",
        environment: git_environment, chdir: directory)
      assert_predicate status, :success?, error
      assert_equal "/api/projects?repository_identity=example.test%2Facme%2Fwidget", request.fetch(:path)
    end
  end

  test "diagnoses unavailable Git checkout remote and remote URL state locally" do
    _output, error, status = run_cli("status", "--remote", "origin", environment: { "PATH" => "" })
    assert_equal [ 2, "git_unavailable" ], [ status.exitstatus, JSON.parse(error).fetch("error") ]

    Dir.mktmpdir("kos-not-checkout") do |directory|
      _output, error, status = run_cli("status", "--remote", "origin", environment: git_environment,
        chdir: directory)
      assert_equal [ 2, "not_a_checkout" ], [ status.exitstatus, JSON.parse(error).fetch("error") ]
    end

    with_git_checkout do |directory, environment|
      _output, error, status = run_cli("status", "--remote", "missing", environment:, chdir: directory)
      assert_equal [ 2, "remote_not_found" ], [ status.exitstatus, JSON.parse(error).fetch("error") ]

      git!(environment, directory, "config", "--local", "remote.empty.fetch", "+refs/heads/*:refs/remotes/empty/*")
      _output, error, status = run_cli("status", "--remote", "empty", environment:, chdir: directory)
      assert_equal [ 2, "remote_url_missing" ], [ status.exitstatus, JSON.parse(error).fetch("error") ]

      git!(environment, directory, "remote", "add", "invalid", "relative/path")
      _output, error, status = run_cli("status", "--remote", "invalid", environment:, chdir: directory)
      assert_equal [ 2, "invalid_remote_url" ], [ status.exitstatus, JSON.parse(error).fetch("error") ]

      git!(environment, directory, "remote", "add", "many", "https://example.test/acme/one.git")
      git!(environment, directory, "config", "--local", "--add", "remote.many.url",
        "https://example.test/acme/two.git")
      _output, error, status = run_cli("status", "--remote", "many", environment:, chdir: directory)
      assert_equal [ 2, "remote_url_ambiguous" ], [ status.exitstatus, JSON.parse(error).fetch("error") ]
    end
  end

  test "preserves status registration authentication and transport failures" do
    with_git_checkout("https://example.test/acme/widget.git") do |directory, git_environment|
      body = JSON.generate(error: "not_found", message: "Project is not registered")
      output, error, status, = run_cli_with_server("status", "--remote", "upstream", response_status: 404,
        response_body: body, environment: git_environment, chdir: directory)
      assert_equal [ 1, body, "" ], [ status.exitstatus, output, error ]

      body = JSON.generate(error: "unauthorized")
      output, error, status, = run_cli_with_server("status", "--remote", "upstream", response_status: 401,
        response_body: body, environment: git_environment, chdir: directory)
      assert_equal [ 1, body, "" ], [ status.exitstatus, output, error ]

      unavailable = TCPServer.new("127.0.0.1", 0)
      port = unavailable.local_address.ip_port
      unavailable.close
      _output, error, status = run_cli("status", "--remote", "upstream", environment: git_environment.merge(
        "KOS_API_URL" => "http://127.0.0.1:#{port}", "KOS_API_TOKEN" => "hidden"), chdir: directory)
      assert_equal [ 3, "transport_error" ], [ status.exitstatus, JSON.parse(error).fetch("error") ]
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

  test "checks matching OpenCode CLI and server installation identities without a token" do
    Dir.mktmpdir("kos-installation-check") do |directory|
      manifest = write_manifest(Pathname(directory).join("kos-installation.json"))
      identity = { status: "ready", version: Kos::VERSION, source_id: Kos::BuildIdentity.installed_source_id }

      output, error, status, request = run_cli_with_server("installation", "check", "--manifest", manifest.to_s,
        response_body: JSON.generate(identity), token: nil)

      assert_predicate status, :success?
      assert_empty error
      assert_equal [ "GET", "/api/ready" ], request.values_at(:method, :path)
      refute request.fetch(:headers).key?("authorization")
      assert_equal identity.merge(manifest: manifest.to_s).stringify_keys, JSON.parse(output)
    end
  end

  test "rejects missing stale and mismatched installation state before workflow operations" do
    Dir.mktmpdir("kos-installation-check") do |directory|
      root = Pathname(directory)
      missing = root.join("missing.json")
      _output, error, status = run_cli("installation", "check", "--manifest", missing.to_s, environment: {})
      assert_equal 2, status.exitstatus
      assert_equal "installation_error", JSON.parse(error).fetch("error")

      stale = write_manifest(root.join("stale.json"), source_id: "sha256:#{"0" * 64}")
      _output, error, status = run_cli("installation", "check", "--manifest", stale.to_s, environment: {})
      assert_equal 1, status.exitstatus
      assert_equal "compatibility_error", JSON.parse(error).fetch("error")

      stale_version = write_manifest(root.join("stale-version.json"), version: "9.9.9")
      _output, error, status = run_cli("installation", "check", "--manifest", stale_version.to_s,
        environment: {})
      assert_equal 1, status.exitstatus
      assert_equal "compatibility_error", JSON.parse(error).fetch("error")

      invalid_inventory = write_manifest(root.join("inventory.json"), skills: %w[kos])
      _output, error, status = run_cli("installation", "check", "--manifest", invalid_inventory.to_s,
        environment: {})
      assert_equal 2, status.exitstatus
      assert_equal "installation_error", JSON.parse(error).fetch("error")
    end
  end

  test "distinguishes server incompatibility from matching server unavailability" do
    Dir.mktmpdir("kos-installation-check") do |directory|
      manifest = write_manifest(Pathname(directory).join("kos-installation.json"))
      mismatch = { status: "ready", version: Kos::VERSION, source_id: "sha256:#{"f" * 64}" }
      _output, error, status, = run_cli_with_server("installation", "check", "--manifest", manifest.to_s,
        response_body: JSON.generate(mismatch), token: nil)
      assert_equal 1, status.exitstatus
      assert_equal "compatibility_error", JSON.parse(error).fetch("error")

      unavailable = { status: "unavailable", version: Kos::VERSION,
                      source_id: Kos::BuildIdentity.installed_source_id }
      _output, error, status, = run_cli_with_server("installation", "check", "--manifest", manifest.to_s,
        response_status: 503, response_body: JSON.generate(unavailable), token: nil)
      assert_equal 1, status.exitstatus
      assert_equal "not_ready", JSON.parse(error).fetch("error")
    end
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
              "--default-branch", "main" ],
              "POST", "/projects", { "name" => "KOS", "remote_url" => "https://example.test/acme/kos.git",
                "default_branch" => "main" } ],
            [ [ "project", "show", "--repository-identity", "example.test/acme/kos" ],
              "GET", "/projects?repository_identity=example.test%2Facme%2Fkos", nil ],
            [ [ "project", "update", "7", "--name", "Renamed" ], "PATCH", "/projects/7", { "name" => "Renamed" } ],
            [ [ "workflow", "create", "--key", "delivery", "--name", "Delivery", "--definition-file",
              definition.path ], "POST", "/workflows", { "key" => "delivery", "name" => "Delivery",
                "definition_json" => { "steps" => [ { "id" => "work" } ] } } ],
            [ [ "workflow", "list" ], "GET", "/workflows", nil ],
            [ [ "workflow", "list", "--key", "delivery" ], "GET", "/workflows?key=delivery", nil ],
            [ [ "workflow", "show", "12" ], "GET", "/workflows/12", nil ],
            [ [ "workflow", "schema" ], "GET", "/workflows/schema", nil ],
            [ [ "plan", "put", "--project-id", "7", "--definition-file", plan.path ],
              "PUT", "/projects/7/plan", { "key" => "goal", "title" => "Goal", "tasks" => [ {
                "key" => "one", "title" => "One", "description_markdown" => "Do it",
                "workflow_key" => "delivery", "blocker_keys" => []
              } ] } ],
            [ [ "plan", "show", "--project-id", "7", "--key", "goal" ],
              "GET", "/projects/7/plan?key=goal", nil ],
            [ [ "plan", "list", "--project-id", "7" ], "GET", "/projects/7/plans", nil ],
            [ [ "plan", "list", "--project-id", "7", "--include-completed" ],
              "GET", "/projects/7/plans?include_completed=true", nil ],
            [ [ "plan", "abandon", "--project-id", "7", "--key", "goal", "--version", "4" ],
              "POST", "/projects/7/plan/abandon", { "key" => "goal", "version" => 4 } ],
            [ [ "task", "list", "--project-id", "7" ], "GET", "/projects/7/tasks", nil ],
            [ [ "task", "list", "--project-id", "7", "--include-completed" ],
              "GET", "/projects/7/tasks?include_completed=true", nil ],
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

  def run_cli_with_server(*arguments, response_status: 200, response_body: "{\"ok\":true}", stdin_data: "",
    token: "test-secret", environment: {}, chdir: nil)
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
      reason = { 200 => "OK", 401 => "Unauthorized", 404 => "Not Found", 409 => "Conflict",
                 503 => "Service Unavailable" }.fetch(response_status)
      socket.write("HTTP/1.1 #{response_status} #{reason}\r\nContent-Type: application/json\r\n" \
        "Content-Length: #{response_body.bytesize}\r\nConnection: close\r\n\r\n#{response_body}")
      socket.close
    ensure
      server.close
    end
    thread.report_on_exception = false

    environment = environment.merge("KOS_API_URL" => "http://127.0.0.1:#{server.local_address.ip_port}/api/")
    environment["KOS_API_TOKEN"] = token if token
    output, error, status = run_cli(*arguments, environment:, stdin_data:, chdir:)
    unless thread.join(2)
      server.close
      thread.kill
      flunk("CLI did not send a request: #{arguments.join(" ")} (stderr: #{error.inspect})")
    end
    [ output, error, status, requests.pop ]
  end

  def run_cli(*arguments, environment:, stdin_data: "", chdir: nil)
    isolated = { "KOS_API_TOKEN" => nil, "KOS_API_URL" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil }.merge(environment)
    options = { stdin_data: }
    options[:chdir] = chdir if chdir
    Open3.capture3(isolated, RbConfig.ruby, "--disable-gems", Rails.root.join("bin/kos").to_s, *arguments,
      **options)
  end

  def with_git_checkout(remote_url = nil)
    Dir.mktmpdir("kos-git-checkout") do |directory|
      environment = git_environment
      git!(environment, directory, "init", "--quiet")
      git!(environment, directory, "remote", "add", "upstream", remote_url) if remote_url
      yield directory, environment
    end
  end

  def git_environment
    { "GIT_CONFIG_NOSYSTEM" => "1", "GIT_CONFIG_GLOBAL" => File::NULL }
  end

  def git!(environment, directory, *arguments)
    _output, error, status = Open3.capture3(environment, "git", "-C", directory.to_s, *arguments)
    assert_predicate status, :success?, error
  end

  def write_manifest(path, version: Kos::VERSION, source_id: Kos::BuildIdentity.installed_source_id,
    commands: Kos::OpenCodeInstallation::INVENTORY.fetch("commands"),
    agents: Kos::OpenCodeInstallation::INVENTORY.fetch("agents"),
    skills: Kos::OpenCodeInstallation::INVENTORY.fetch("skills"))
    path.write(JSON.generate(schema: Kos::OpenCodeInstallation::SCHEMA, version:, source_id:,
      commands:, agents:, skills:))
    path
  end
end
