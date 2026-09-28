require "json"
require "net/http"
require "openssl"
require "optparse"
require "securerandom"
require "uri"
require "kos/api_token"
require "kos/build_identity"
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

    def initialize(arguments, environment: ENV, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      @arguments = arguments.dup
      @environment = environment
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
    end

    def run
      return print_version if @arguments == [ "--version" ] || @arguments == [ "-v" ]
      return print_help if @arguments.empty? || @arguments == [ "--help" ] || @arguments == [ "-h" ]
      return claim_id if @arguments.first == "claim-id"

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
          project create | show | update
          workflow create
          plan put | list | show
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

    def command
      resource = @arguments.shift
      action = @arguments.shift

      case [ resource, action ]
      when [ "health", nil ] then [ :get, "/up", nil ]
      when [ "project", "create" ] then project_create
      when [ "project", "show" ] then project_show
      when [ "project", "update" ] then project_update
      when [ "workflow", "create" ] then workflow_create
      when [ "plan", "put" ] then plan_put
      when [ "plan", "list" ] then plan_list
      when [ "plan", "show" ] then plan_show
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

    def project_create
      values = parse_options("kos project create", project_options)
      require_values!(values, :name, :remote_url, :default_branch)
      [ :post, "/projects", values ]
    end

    def project_show
      values = parse_options("kos project show", {
        "--repository-identity IDENTITY" => [ :repository_identity, String, "Canonical host/namespace/repository" ]
      })
      require_values!(values, :repository_identity)
      [ :get, query_path("/projects", values), nil ]
    end

    def project_update
      id = shift_id!("project")
      values = parse_options("kos project update ID", project_options)
      raise Error.new("usage_error", "provide at least one project field") if values.empty?

      [ :patch, "/projects/#{id}", values ]
    end

    def workflow_create
      values = parse_options("kos workflow create", {
        "--key KEY" => [ :key, String, "Stable workflow key" ],
        "--name NAME" => [ :name, String, "Workflow name" ],
        "--definition-file FILE" => [ :definition_file, String, "Workflow JSON file, or - for STDIN" ]
      })
      require_values!(values, :key, :name, :definition_file)
      values[:definition_json] = read_json_object(values.delete(:definition_file))
      [ :post, "/workflows", values ]
    end

    def plan_put
      values = parse_options("kos plan put", {
        "--project-id ID" => [ :project_id, Integer, "Project ID" ],
        "--definition-file FILE" => [ :definition_file, String, "Plan JSON file, or - for STDIN" ]
      }, footer: "Plan JSON fields: key, title, tasks. Each task requires exactly: " \
        "key, title, description_markdown, workflow_key, blocker_keys.")
      require_values!(values, :project_id, :definition_file)
      project_id = values.delete(:project_id)
      [ :put, "/projects/#{project_id}/plan", read_json_object(values.delete(:definition_file)) ]
    end

    def plan_show
      values = parse_options("kos plan show", {
        "--project-id ID" => [ :project_id, Integer, "Project ID" ],
        "--key KEY" => [ :key, String, "Task plan key" ]
      })
      require_values!(values, :project_id, :key)
      project_id = values.delete(:project_id)
      [ :get, query_path("/projects/#{project_id}/plan", values), nil ]
    end

    def plan_list
      project_id, values = project_list_options("kos plan list",
        "Response task_plans fields: id, project_id, key, title, created_at, updated_at")
      [ :get, query_path("/projects/#{project_id}/plans", values), nil ]
    end

    def task_list
      project_id, values = project_list_options("kos task list",
        "Response tasks fields: id, task_plan_id, workflow_id, key, title, status, current_step, claim_id, " \
        "version, pause_kind, pause_message, pause_step, answer, created_at, updated_at, blocker_ids")
      [ :get, query_path("/projects/#{project_id}/tasks", values), nil ]
    end

    def task_ready
      values = parse_options("kos task ready", {
        "--project-id ID" => [ :project_id, Integer, "Project ID" ]
      })
      require_values!(values, :project_id)
      [ :get, query_path("/tasks/ready", values), nil ]
    end

    def task_show
      id = shift_id!("task")
      parse_options("kos task show ID", {})
      [ :get, "/tasks/#{id}", nil ]
    end

    def task_context
      id = shift_id!("task")
      parse_options("kos task context ID", {})
      [ :get, "/tasks/#{id}/context", nil ]
    end

    def task_result
      id = shift_id!("task")
      values = parse_options("kos task result ID", {
        "--step STEP" => [ :step, String, "Workflow step" ]
      })
      require_values!(values, :step)
      [ :get, query_path("/tasks/#{id}/result", values), nil ]
    end

    def task_claim
      id = shift_id!("task")
      values = parse_options("kos task claim ID", claim_options.merge(
        "--version VERSION" => [ :version, Integer, "Observed task version" ]
      ))
      require_values!(values, :claim_id, :version)
      [ :post, "/tasks/#{id}/claim", values ]
    end

    def task_takeover
      id = shift_id!("task")
      values = parse_options("kos task takeover ID", claim_options.merge(
        "--version VERSION" => [ :version, Integer, "Observed task version" ],
        "--step STEP" => [ :step, String, "Observed current step" ]
      ))
      require_values!(values, :claim_id, :version, :step)
      [ :post, "/tasks/#{id}/takeover", values ]
    end

    def task_report
      id = shift_id!("task")
      values = parse_options("kos task report ID", fence_options.merge(
        "--outcome OUTCOME" => [ :outcome, String, "Reported step outcome" ],
        "--result-file FILE" => [ :result_file, String, "Step result, or - for STDIN" ],
        "--message MESSAGE" => [ :message, String, "Question or obstruction for a pause" ]
      ))
      require_values!(values, :claim_id, :version, :step, :outcome, :result_file)
      values[:result] = read_file(values.delete(:result_file))
      [ :post, "/tasks/#{id}/report", values ]
    end

    def task_answer
      id = shift_id!("task")
      values = parse_options("kos task answer ID", {
        "--version VERSION" => [ :version, Integer, "Observed task version" ],
        "--step STEP" => [ :step, String, "Paused workflow step" ],
        "--answer-file FILE" => [ :answer_file, String, "Answer, or - for STDIN" ]
      })
      require_values!(values, :version, :step, :answer_file)
      values[:answer] = read_file(values.delete(:answer_file))
      [ :post, "/tasks/#{id}/answer", values ]
    end

    def project_options
      {
        "--name NAME" => [ :name, String, "Project name" ],
        "--remote-url URL" => [ :remote_url, String, "Git remote URL" ],
        "--default-branch BRANCH" => [ :default_branch, String, "Default Git branch" ],
        "--repository-identity IDENTITY" => [ :repository_identity, String, "Canonical host/namespace/repository" ]
      }
    end

    def claim_options
      { "--claim-id CLAIM" => [ :claim_id, String, "Worker claim ID" ] }
    end

    def fence_options
      claim_options.merge(
        "--version VERSION" => [ :version, Integer, "Observed task version" ],
        "--step STEP" => [ :step, String, "Observed current step" ]
      )
    end

    def project_list_options(usage, response_help)
      values = parse_options(usage, {
        "--project-id ID" => [ :project_id, Integer, "Project ID" ],
        "--include-completed" => [ :include_completed, nil, "Include completed state" ]
      }, footer: response_help)
      require_values!(values, :project_id)
      [ values.delete(:project_id), values ]
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
      http_request["Authorization"] = "Bearer #{api_token}" unless path == "/up"
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
