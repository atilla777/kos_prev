require "json"
require "net/http"
require "openssl"
require "optparse"
require "securerandom"
require "uri"
require "kos/api_token"
require "kos/build_identity"
require "kos/git_remote"
require "kos/open_code_installation"
require "kos/repository_identity"
require "kos/workflow_definition"
require_relative "version"

module Kos
  class CLI
    DEFAULT_API_URL = "http://127.0.0.1:3000"

    class Error < StandardError
      attr_reader :kind, :exit_status

      def initialize(kind, message, exit_status: 2)
        @kind = kind
        @exit_status = exit_status
        super(message)
      end
    end

    def initialize(arguments, environment: ENV, stdin: $stdin, stdout: $stdout, stderr: $stderr, git_remote: nil)
      @arguments = arguments.dup
      @environment = environment
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @git_remote = git_remote || Kos::GitRemote.new(environment:)
    end

    def run
      return print_version if @arguments == [ "--version" ] || @arguments == [ "-v" ]
      return print_help if @arguments.empty? || @arguments == [ "--help" ] || @arguments == [ "-h" ]
      return claim_id if @arguments.first == "claim-id"
      return installation_check if @arguments.first(2) == %w[installation check]

      method, path, payload = command
      response = request(method, path, payload)
      @stdout.write(response.body) unless response.body.to_s.empty?
      response.is_a?(Net::HTTPSuccess) ? 0 : 1
    rescue Error => error
      write_error(error.kind, error.message)
      error.exit_status
    rescue OptionParser::ParseError => error
      write_error("usage_error", error.message)
      2
    end

    private

    def print_version
      @stdout.puts("kos #{Kos::VERSION} source=#{Kos::BuildIdentity.installed_source_id}")
      0
    end

    def print_help
      @stdout.puts <<~HELP
        Usage: kos <resource> <action> [options]

        KOS task coordination CLI

        Resources and actions:
          health
          claim-id
          installation check
          project create | show | resolve | update
          status
          workflow create | list | show | schema
          plan put | list | show | abandon
          task list | ready | show | context | result | claim | takeover | report | answer

        Options:
          -v, --version             Show the installed CLI version

        Run `kos <resource> <action> --help` for command options.
      HELP
      0
    end

    def claim_id
      @arguments.shift
      parse_options("kos claim-id", {})
      @stdout.puts("kos-claim-#{SecureRandom.hex(16)}")
      0
    end

    def installation_check
      @arguments.shift(2)
      values = parse_options("kos installation check", {
        "--manifest PATH" => [ :manifest, String, "Absolute OpenCode installation manifest path" ]
      })
      manifest_path = Kos::OpenCodeInstallation.manifest_path(environment: @environment, explicit: values[:manifest])
      manifest = Kos::OpenCodeInstallation.read_manifest(manifest_path, require_current_inventory: true)
      cli_identity = { "version" => Kos::VERSION, "source_id" => Kos::BuildIdentity.installed_source_id }
      require_matching_identity!("OpenCode manifest", manifest, "installed CLI", cli_identity)

      response = request(:get, "/ready", nil)
      server = parse_identity_response(response)
      require_matching_identity!("installed CLI", cli_identity, "KOS server", server)
      unless response.is_a?(Net::HTTPSuccess) && server["status"] == "ready"
        raise Error.new("not_ready",
          "KOS server matches this installation but is not ready; run database preparation and seeding, then retry",
          exit_status: 1)
      end

      @stdout.puts(JSON.generate(status: "ready", version: cli_identity.fetch("version"),
        source_id: cli_identity.fetch("source_id"), manifest: manifest_path.to_s))
      0
    rescue Kos::OpenCodeInstallation::Invalid => error
      raise Error.new("installation_error",
        "#{error.message}; reinstall the CLI and OpenCode integration from one KOS release")
    end

    def command
      resource = @arguments.shift
      action = @arguments.shift unless resource == "status"

      case [ resource, action ]
      when [ "health", nil ] then [ :get, "/up", nil ]
      when [ "project", "create" ] then project_create
      when [ "project", "show" ] then project_show
      when [ "project", "resolve" ] then project_resolve
      when [ "project", "update" ] then project_update
      when [ "status", nil ] then status
      when [ "workflow", "list" ] then workflow_list
      when [ "workflow", "show" ] then workflow_show
      when [ "workflow", "schema" ] then workflow_schema
      when [ "workflow", "create" ] then workflow_create
      when [ "plan", "put" ] then plan_put
      when [ "plan", "list" ] then plan_list
      when [ "plan", "show" ] then plan_show
      when [ "plan", "abandon" ] then plan_abandon
      when [ "task", "list" ] then task_list
      when [ "task", "ready" ] then task_ready
      when [ "task", "show" ] then task_show
      when [ "task", "context" ] then task_context
      when [ "task", "result" ] then task_result
      when [ "task", "claim" ] then task_claim
      when [ "task", "takeover" ] then task_takeover
      when [ "task", "report" ] then task_report
      when [ "task", "answer" ] then task_answer
      else
        raise Error.new("usage_error", "unknown command #{[ resource, action ].compact.join(" ").inspect}")
      end
    end

    def parse_identity_response(response)
      value = JSON.parse(response.body.to_s)
      unless value.is_a?(Hash) && value["version"].is_a?(String) &&
          value["source_id"].is_a?(String) && value["source_id"].match?(Kos::OpenCodeInstallation::SOURCE_ID_PATTERN)
        raise Error.new("compatibility_error", "KOS server readiness response has no valid release identity", exit_status: 1)
      end

      value
    rescue JSON::ParserError
      raise Error.new("compatibility_error", "KOS server readiness response is not valid JSON", exit_status: 1)
    end

    def require_matching_identity!(left_name, left, right_name, right)
      return if %w[version source_id].all? { |field| left[field] == right[field] }

      raise Error.new("compatibility_error",
        "#{left_name} and #{right_name} are from different KOS releases; reinstall all components from one release and fully restart OpenCode",
        exit_status: 1)
    end

  def project_create
      values = parse_options("kos project create", project_options(required: true), footer: <<~HELP)
        Response: project with #{project_response_fields}.
        Example: kos project create --name Widget --remote-url git@github.com:acme/widget.git --default-branch main
      HELP
      require_values!(values, :name, :remote_url, :default_branch)
      [ :post, "/projects", values ]
    end

    def project_show
      values = parse_options("kos project show", {
        "--repository-identity IDENTITY" => [ :repository_identity, String,
          "Required canonical host/namespace/repository" ]
      }, footer: <<~HELP)
        Response: project with #{project_response_fields}.
        Example: kos project show --repository-identity github.com/acme/widget
      HELP
      require_values!(values, :repository_identity)
      [ :get, query_path("/projects", values), nil ]
    end

    def project_resolve
      identity = resolved_repository_identity("kos project resolve")
      [ :get, query_path("/projects", repository_identity: identity), nil ]
    end

    def status
      identity = resolved_repository_identity("kos status", footer: <<~HELP)
        Response: project with #{project_response_fields}; task_plans[] and tasks[] contain default non-completed recovery state.
        Status is observational and does not classify claims or perform lifecycle writes.
        Example: kos status --remote origin
      HELP
      [ :get, query_path("/status", repository_identity: identity), nil ]
    end

    def project_update
      id = shift_id!("project")
      values = parse_options("kos project update ID", project_options, footer: <<~HELP)
        ID: required numeric project ID returned by project create or project show.
        Provide at least one project field. Response: project with #{project_response_fields}.
        Example: kos project update 7 --name "Renamed widget"
      HELP
      raise Error.new("usage_error", "provide at least one project field") if values.empty?

      [ :patch, "/projects/#{id}", values ]
    end

    def workflow_list
      values = parse_options("kos workflow list", {
        "--key KEY" => [ :key, String, "Optional exact workflow key filter" ]
      }, footer: <<~HELP)
        Response: workflows[] with id, key, name, revision, definition_json, and created_at.
        Example: kos workflow list --key development
      HELP
      [ :get, query_path("/workflows", values), nil ]
    end

    def workflow_show
      id = shift_id!("workflow")
      parse_options("kos workflow show ID", {}, footer: <<~HELP)
        ID: required numeric immutable workflow revision ID returned by workflow list; it is not a key or revision number.
        Response: workflow with id, key, name, revision, definition_json, and created_at.
        Example: kos workflow show 12
      HELP
      [ :get, "/workflows/#{id}", nil ]
    end

    def workflow_schema
      parse_options("kos workflow schema", {}, footer: <<~HELP)
        Response: schema contains the authoritative definition contract; example is one valid complete definition_json.
        Example: kos workflow schema
      HELP
      [ :get, "/workflows/schema", nil ]
    end

    def workflow_create
      values = parse_options("kos workflow create", {
        "--key KEY" => [ :key, String, "Required stable workflow key" ],
        "--name NAME" => [ :name, String, "Required workflow name" ],
        "--definition-file FILE" => [ :definition_file, String, "Required definition_json file, or - for STDIN" ]
      }, footer: workflow_definition_help)
      require_values!(values, :key, :name, :definition_file)
      values[:definition_json] = read_json_object(values.delete(:definition_file))
      [ :post, "/workflows", values ]
    end

    def plan_put
      values = parse_options("kos plan put", {
        "--project-id ID" => [ :project_id, Integer, "Required numeric project ID" ],
        "--definition-file FILE" => [ :definition_file, String, "Required plan JSON file, or - for STDIN" ]
      }, footer: <<~HELP)
        Input object: key, title, tasks. Each task requires exactly key, title, description_markdown,
        workflow_key, and blocker_keys. Response: #{plan_response_fields}.
        Example: kos plan put --project-id 7 --definition-file plan.json
      HELP
      require_values!(values, :project_id, :definition_file)
      project_id = values.delete(:project_id)
      [ :put, "/projects/#{project_id}/plan", read_json_object(values.delete(:definition_file)) ]
    end

    def plan_show
      values = parse_options("kos plan show", {
        "--project-id ID" => [ :project_id, Integer, "Required numeric project ID" ],
        "--key KEY" => [ :key, String, "Required task plan key" ]
      }, footer: <<~HELP)
        Response: #{plan_response_fields}.
        Example: kos plan show --project-id 7 --key release
      HELP
      require_values!(values, :project_id, :key)
      project_id = values.delete(:project_id)
      [ :get, query_path("/projects/#{project_id}/plan", values), nil ]
    end

    def plan_list
      project_id, values = project_list_options("kos plan list",
        "Response task_plans fields: id, project_id, key, title, status, version, created_at, updated_at.\n" \
        "Example: kos plan list --project-id 7")
      [ :get, query_path("/projects/#{project_id}/plans", values), nil ]
    end

    def plan_abandon
      values = parse_options("kos plan abandon", {
        "--project-id ID" => [ :project_id, Integer, "Required numeric project ID" ],
        "--key KEY" => [ :key, String, "Required task plan key" ],
        "--version VERSION" => [ :version, Integer, "Required observed task plan version" ]
      }, footer: <<~HELP)
        Response: #{plan_response_fields}. Use only with explicit intent.
        Example: kos plan abandon --project-id 7 --key obsolete --version 4
      HELP
      require_values!(values, :project_id, :key, :version)
      project_id = values.delete(:project_id)
      [ :post, "/projects/#{project_id}/plan/abandon", values ]
    end

    def task_list
      project_id, values = project_list_options("kos task list",
        "Response tasks fields: id, task_plan_id, workflow_id, workflow_key, workflow_revision, key, title, " \
        "status, current_step, claim_id, version, pause_kind, pause_message, pause_step, answer, created_at, " \
        "updated_at, blocker_ids.\nExample: kos task list --project-id 7")
      [ :get, query_path("/projects/#{project_id}/tasks", values), nil ]
    end

    def task_ready
      values = parse_options("kos task ready", {
        "--project-id ID" => [ :project_id, Integer, "Required numeric project ID" ]
      }, footer: <<~HELP)
        Response: tasks[] with #{task_response_fields}.
        Example: kos task ready --project-id 7
      HELP
      require_values!(values, :project_id)
      [ :get, query_path("/tasks/ready", values), nil ]
    end

    def task_show
      id = shift_id!("task")
      parse_options("kos task show ID", {}, footer: task_id_help(
        "task with #{task_response_fields}", "kos task show 9"))
      [ :get, "/tasks/#{id}", nil ]
    end

    def task_context
      id = shift_id!("task")
      parse_options("kos task context ID", {}, footer: task_id_help(
        "task with #{task_response_fields} and description_markdown; task_plan with id, project_id, key, title, " \
        "status, version; project with id, name, repository_identity, remote_url, default_branch; workflow with " \
        "id, key, revision; step with id, name, instruction, outcomes, allowed_outcomes; results[] with step, outcome; " \
        "pause with kind, step, message, answer", "kos task context 9"))
      [ :get, "/tasks/#{id}/context", nil ]
    end

    def task_result
      id = shift_id!("task")
      values = parse_options("kos task result ID", {
        "--step STEP" => [ :step, String, "Required executed workflow step ID" ]
      }, footer: task_id_help("outcome and result for STEP", "kos task result 9 --step review"))
      require_values!(values, :step)
      [ :get, query_path("/tasks/#{id}/result", values), nil ]
    end

    def task_claim
      id = shift_id!("task")
      values = parse_options("kos task claim ID", claim_options.merge(
        "--version VERSION" => [ :version, Integer, "Required observed task version" ]
      ), footer: task_id_help("task with #{task_response_fields}", \
        "kos task claim 9 --claim-id CLAIM --version 0"))
      require_values!(values, :claim_id, :version)
      [ :post, "/tasks/#{id}/claim", values ]
    end

    def task_takeover
      id = shift_id!("task")
      values = parse_options("kos task takeover ID", claim_options.merge(
        "--version VERSION" => [ :version, Integer, "Required observed task version" ],
        "--step STEP" => [ :step, String, "Required observed current step" ]
      ), footer: task_id_help("task with #{task_response_fields}", \
        "kos task takeover 9 --claim-id NEW --version 2 --step work"))
      require_values!(values, :claim_id, :version, :step)
      [ :post, "/tasks/#{id}/takeover", values ]
    end

    def task_report
      id = shift_id!("task")
      values = parse_options("kos task report ID", fence_options.merge(
        "--outcome OUTCOME" => [ :outcome, String, "Required allowed step outcome" ],
        "--result-file FILE" => [ :result_file, String, "Required step result, or - for STDIN" ],
        "--message MESSAGE" => [ :message, String, "Required question or obstruction for a pause outcome" ]
      ), footer: task_id_help("task with #{task_response_fields}", \
        "kos task report 9 --claim-id CLAIM --version 1 --step work --outcome done --result-file result.md") +
        "\nOUTCOME must be allowed by task context; --message is required by a pause outcome.")
      require_values!(values, :claim_id, :version, :step, :outcome, :result_file)
      values[:result] = read_file(values.delete(:result_file))
      [ :post, "/tasks/#{id}/report", values ]
    end

    def task_answer
      id = shift_id!("task")
      values = parse_options("kos task answer ID", {
        "--version VERSION" => [ :version, Integer, "Required observed task version" ],
        "--step STEP" => [ :step, String, "Required paused workflow step" ],
        "--answer-file FILE" => [ :answer_file, String, "Required answer, or - for STDIN" ]
      }, footer: task_id_help("task with #{task_response_fields}", \
        "kos task answer 9 --version 3 --step work --answer-file answer.md"))
      require_values!(values, :version, :step, :answer_file)
      values[:answer] = read_file(values.delete(:answer_file))
      [ :post, "/tasks/#{id}/answer", values ]
    end

    def project_options(required: false)
      prefix = required ? "Required" : "Optional"
      {
        "--name NAME" => [ :name, String, "#{prefix} project name" ],
        "--remote-url URL" => [ :remote_url, String, "#{prefix} Git remote URL" ],
        "--default-branch BRANCH" => [ :default_branch, String, "#{prefix} default Git branch" ],
        "--repository-identity IDENTITY" => [ :repository_identity, String,
          "Optional canonical host/namespace/repository" ]
      }
    end

    def resolved_repository_identity(usage, footer: nil)
      values = parse_options(usage, {
        "--remote NAME" => [ :remote, String, "Required explicitly selected Git remote name" ]
      }, footer: footer || <<~HELP)
        Response: project with #{project_response_fields}.
        Reads only the selected remote URL from the current Git checkout.
        Example: kos project resolve --remote origin
      HELP
      require_values!(values, :remote)
      remote_url = normalize_utf8(@git_remote.url(values.fetch(:remote)), "Git remote URL")
      Kos::RepositoryIdentity.normalize(remote_url)
    rescue Kos::GitRemote::Error => error
      raise Error.new(error.kind, error.message)
    rescue Kos::RepositoryIdentity::Invalid => error
      raise Error.new("invalid_remote_url", "selected Git remote URL is unsupported: #{error.message}")
    end

    def claim_options
      { "--claim-id CLAIM" => [ :claim_id, String, "Required worker claim ID from claim-id" ] }
    end

    def fence_options
      claim_options.merge(
        "--version VERSION" => [ :version, Integer, "Required observed task version" ],
        "--step STEP" => [ :step, String, "Required observed current step" ]
      )
    end

    def project_list_options(usage, response_help)
      values = parse_options(usage, {
        "--project-id ID" => [ :project_id, Integer, "Required numeric project ID" ],
        "--include-completed" => [ :include_completed, nil, "Optional inclusion of completed state" ]
      }, footer: response_help)
      require_values!(values, :project_id)
      [ values.delete(:project_id), values ]
    end

    def workflow_definition_help
      contract = Kos::WorkflowDefinition::CONTRACT
      steps = contract.fetch("steps")
      fields = steps.fetch("item").fetch("fields")
      <<~HELP
        Input definition_json is an object containing exactly steps, a non-empty array of at most #{steps.fetch("maximum")}.
        Each step contains exactly id, name, instruction, outcomes.
        id, name, instruction, and outcome names are nonblank valid UTF-8 strings.
        id and outcome names are at most #{fields.dig("id", "maximum_bytes")} bytes; name is at most
        #{fields.dig("name", "maximum_bytes")} bytes; instruction is at most
        #{fields.dig("instruction", "maximum_bytes")} bytes. outcomes is a non-empty object,
        with at most #{fields.dig("outcomes", "total_maximum")} outcomes across the workflow. Each outcome has exactly
        one transition: {"next_step":"STEP_ID"}, {"pause":"needs_human"}, {"pause":"blocked"}, or
        {"complete_task":true}. Step ids are unique, next_step targets exist, the first step is initial, and every
        reachable step has a path to complete_task.
        Complete valid example:
        #{JSON.pretty_generate(Kos::WorkflowDefinition.example)}
        Response: workflow with id, key, name, revision, definition_json, and created_at.
        Example: kos workflow create --key delivery --name Delivery --definition-file workflow.json
      HELP
    end

    def task_id_help(response, example)
      "ID: required numeric task ID returned by task list, task ready, or plan show.\n" \
        "Response: #{response}.\nExample: #{example}"
    end

    def task_response_fields
      "id, task_plan_id, workflow_id, workflow_key, workflow_revision, key, title, status, current_step, " \
        "claim_id, version, pause_kind, pause_message, pause_step, answer, created_at, updated_at, and blocker_ids"
    end

    def project_response_fields
      "id, name, repository_identity, remote_url, default_branch, created_at, and updated_at"
    end

    def plan_response_fields
      "task_plan with id, project_id, key, title, status, version, created_at, updated_at; tasks[] with id, key, " \
        "title, description_markdown, status, current_step, claim_id, version, workflow id/key/revision, and blocker_keys"
    end

    def parse_options(usage, definitions, footer: nil)
      values = {}
      parser = OptionParser.new do |option_parser|
        option_parser.banner = "Usage: #{usage} [options]"
        option_parser.on("-h", "--help", "Show this help") do
          @stdout.puts(option_parser)
          throw :help
        end
      end
      definitions.each do |switch, (name, type, description)|
        if type
          parser.on(switch, type, description) { |value| values[name] = value }
        else
          parser.on(switch, description) { values[name] = true }
        end
      end
      parser.separator("\n#{footer}") if footer
      parse!(parser)
      values
    end

    def parse!(parser)
      helped = catch(:help) do
        parser.parse!(@arguments)
        false
      end
      throw :command_help if helped.nil?
      raise OptionParser::InvalidArgument, "unexpected arguments: #{@arguments.join(" ")}" if @arguments.any?
    rescue ArgumentError => error
      raise Error.new("usage_error", error.message)
    end

    def require_values!(values, *names)
      missing = names.reject { |name| values.key?(name) }
      return if missing.empty?

      switches = missing.map { |name| "--#{name.to_s.tr("_", "-")}" }
      raise Error.new("usage_error", "missing required options: #{switches.join(", ")}")
    end

    def shift_id!(label)
      return 0 if %w[-h --help].include?(@arguments.first)

      Integer(@arguments.shift, 10)
    rescue ArgumentError, TypeError
      raise Error.new("usage_error", "#{label} ID must be an integer")
    end

    def read_json_object(path)
      value = JSON.parse(read_file(path))
      raise Error.new("local_input_error", "JSON in #{display_path(path)} must be an object") unless value.is_a?(Hash)

      value
    rescue JSON::ParserError => error
      raise Error.new("local_input_error", "invalid JSON in #{display_path(path)}: #{error.message}")
    end

    def read_file(path)
      contents = path == "-" ? @stdin.read : File.binread(path)
      normalize_utf8(contents, display_path(path))
    rescue SystemCallError => error
      raise Error.new("local_input_error", "cannot read #{display_path(path)}: #{error.message}")
    end

    def display_path(path)
      path == "-" ? "STDIN" : path
    end

    def request(method, path, payload)
      uri = endpoint(path)
      request_class = { get: Net::HTTP::Get, patch: Net::HTTP::Patch, post: Net::HTTP::Post,
                        put: Net::HTTP::Put }.fetch(method)
      http_request = request_class.new(uri)
      http_request["Accept"] = "application/json"
      http_request["Authorization"] = "Bearer #{api_token}" unless %w[/up /ready].include?(path)
      if payload
        http_request["Content-Type"] = "application/json"
        http_request.body = JSON.generate(normalize_payload(payload))
      end

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
        http.request(http_request)
      end
    rescue SocketError, SystemCallError, IOError, EOFError, Net::OpenTimeout, Net::ReadTimeout,
      Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, OpenSSL::SSL::SSLError => error
      raise Error.new("transport_error", "request to #{uri&.host || "KOS"} failed: #{error.message}", exit_status: 3)
    end

    def endpoint(path)
      raw_url = @environment.fetch("KOS_API_URL", DEFAULT_API_URL)
      uri = URI.parse(raw_url)
      unless %w[http https].include?(uri.scheme) && uri.host && !uri.query && !uri.fragment
        raise Error.new("configuration_error", "KOS_API_URL must be an HTTP(S) base URL")
      end

      request_path, query = path.split("?", 2)
      uri.path = [ uri.path.sub(%r{/+$}, ""), request_path ].join
      uri.query = query
      uri
    rescue URI::InvalidURIError
      raise Error.new("configuration_error", "KOS_API_URL must be an HTTP(S) base URL")
    end

    def query_path(path, values)
      return path if values.empty?

      "#{path}?#{URI.encode_www_form(values)}"
    end

    def api_token
      token = Kos::ApiToken.normalize(@environment["KOS_API_TOKEN"])
      return token if token

      raise Error.new("configuration_error", "KOS_API_TOKEN must be a non-empty HTTP header value")
    end

    def normalize_payload(value)
      case value
      when Hash then value.transform_values { |item| normalize_payload(item) }
      when Array then value.map { |item| normalize_payload(item) }
      when String then normalize_utf8(value, "request data")
      else value
      end
    end

    def normalize_utf8(value, label)
      utf8 = value.b.dup.force_encoding(Encoding::UTF_8)
      return utf8 if utf8.valid_encoding?

      raise Error.new("local_input_error", "#{label} must be valid UTF-8")
    end

    def write_error(kind, message)
      safe_message = message.to_s.b.force_encoding(Encoding::UTF_8).scrub
      @stderr.puts(JSON.generate(error: kind, message: safe_message))
    end
  end
end
