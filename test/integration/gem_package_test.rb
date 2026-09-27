require "test_helper"
require "json"
require "net/http"
require "open3"
require "rbconfig"
require "socket"
require "tempfile"
require "tmpdir"
require "timeout"

class GemPackageTest < ActiveSupport::TestCase
  test "builds and installs a standalone kos executable" do
    Dir.mktmpdir("kos-gem") do |directory|
      root = Pathname(directory)
      package = root.join("kos.gem")
      gem_home = root.join("gem-home")
      bin_dir = root.join("bin")

      _output, error, status = Open3.capture3(RbConfig.ruby, "-S", "gem", "build", "kos.gemspec",
        "--output", package.to_s, chdir: Rails.root.to_s)
      assert_predicate status, :success?, error

      _output, error, status = Open3.capture3(RbConfig.ruby, "-S", "gem", "install", package.to_s,
        "--install-dir", gem_home.to_s, "--bindir", bin_dir.to_s, "--no-document")
      assert_predicate status, :success?, error

      environment = {
        "BUNDLE_GEMFILE" => nil, "GEM_HOME" => gem_home.to_s, "GEM_PATH" => gem_home.to_s,
        "RUBYGEMS_GEMDEPS" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil
      }
      output, error, status = Open3.capture3(environment, bin_dir.join("kos").to_s, "--version", chdir: directory)

      assert_predicate status, :success?, error
      assert_equal "kos #{Kos::VERSION}\n", output
      assert_empty error

      session_id, error, status = Open3.capture3(environment.merge("KOS_API_URL" => "invalid"),
        bin_dir.join("kos").to_s, "session-id", chdir: directory)
      assert_predicate status, :success?, error
      assert_match(/\Akos-session-[0-9a-f]{32}\n\z/, session_id)
      assert_empty error

      output, error, status = Open3.capture3(environment, bin_dir.join("kos").to_s, "--help", chdir: directory)
      assert_predicate status, :success?, error
      assert_match(/^\s*health\s*$/, output)
      {
        "project" => %w[create show update],
        "workflow" => %w[create],
        "task-type" => %w[create update],
        "task" => %w[
          create create-or-get create-and-claim update show context artifact show-owned claim-next claim resumable resume
          report-attempt cancel materialize-children children
        ]
      }.each do |resource, actions|
        inventory = output.lines.grep(/^\s*#{Regexp.escape(resource)}\s+/).join
        assert_not_empty inventory
        actions.each { |action| assert_match(/\b#{Regexp.escape(action)}\b/, inventory) }
      end

      {
        %w[task context] => [],
        %w[task artifact] => %w[--step],
        %w[task report-attempt] => %w[--claim-version --artifact-file]
      }.each do |command, options|
        command_output, command_error, command_status = Open3.capture3(
          environment, bin_dir.join("kos").to_s, *command, "--help", chdir: directory
        )
        assert_predicate command_status, :success?, command_error
        assert_match(/Usage: kos #{Regexp.escape(command.join(" "))}/, command_output)
        options.each { |option| assert_includes command_output, option }
      end
    end
  end

  test "installed CLI drives a prepared server through the core lifecycle" do
    with_installed_cli do |cli, cli_environment, root|
      system = { data_home: root.join("data"), token: "smoke-secret", log: root.join("server.log") }
      _output, error, status = Open3.capture3(server_environment(system), Rails.root.join("bin/rails").to_s,
        "db:prepare")
      assert_predicate status, :success?, error

      start_server(system)
      environment = cli_environment.merge("KOS_API_URL" => system.fetch(:api_url))
      output, error, status = Open3.capture3(environment, cli.to_s, "health", chdir: root.to_s)
      assert_predicate status, :success?, error
      assert_not_empty output

      authenticated = environment.merge("KOS_API_TOKEN" => system.fetch(:token))
      project = run_installed_json(cli, authenticated, root, "project", "create", "--name", "Smoke",
        "--remote-url", "https://example.test/test/smoke.git", "--default-branch", "main").fetch("project")
      shown = run_installed_json(cli, authenticated, root, "project", "show", "--repository-identity",
        "example.test/test/smoke").fetch("project")
      assert_equal project.fetch("id"), shown.fetch("id")

      Tempfile.create([ "smoke-task", ".md" ], root.to_s) do |artifact|
        artifact.write("# Smoke task\n")
        artifact.flush
        task = run_installed_json(cli, authenticated, root, "task", "create", "--project-id",
          project.fetch("id").to_s, "--task-type-key", "development", "--title", "Smoke lifecycle",
          "--description-file", artifact.path).fetch("task")
        task = run_installed_json(cli, authenticated, root, "task", "claim", task.fetch("id").to_s,
          "--owner-id", "smoke-owner").fetch("task")

        {
          "plan" => "planned", "implement" => "implemented", "document" => "documented",
          "review" => "approved", "publish" => "published"
        }.each do |step, outcome|
          check_options = step == "implement" ? [ "--required-checks", "passed" ] : []
          task = run_installed_json(cli, authenticated, root, "task", "report-attempt", task.fetch("id").to_s,
            "--owner-id", "smoke-owner", "--claim-version", task.fetch("claim_version").to_s,
            "--step", step, "--outcome", outcome, "--artifact-file", artifact.path, *check_options).fetch("task")
        end

        context = run_installed_json(cli, authenticated, root, "task", "context", task.fetch("id").to_s)
        assert_equal [ "completed", "publish", nil, nil ],
          context.fetch("task").values_at("status", "current_step", "owner_id", "lease_expires_at")
        assert_equal %w[plan implement document review publish],
          context.fetch("artifacts").map { |entry| entry.fetch("step") }
        assert_equal "passed", context.fetch("artifacts").find { |entry| entry.fetch("step") == "implement" }
          .fetch("required_checks")
      end
    ensure
      stop_server(system) if system
    end
  end

  test "installs the complete OpenCode integration from the checkout" do
    Dir.mktmpdir("kos-opencode") do |directory|
      root = Pathname(directory)
      config_home = root.join("config/opencode")
      stale_agent = config_home.join("agents/kos-step.md")
      stale_orchestrator = config_home.join("agents/kos-orchestrator.md")
      stale_verifier = config_home.join("agents/kos-verify.md")
      obsolete_role_agents = %w[brief diagnose document implement plan publish review].map do |role|
        config_home.join("agents/kos-#{role}.md")
      end
      stale_skill = config_home.join("skills/kos/obsolete.md")
      obsolete_brief_skill = config_home.join("skills/kos-brief/SKILL.md")
      obsolete_create_skill = config_home.join("skills/kos-create/SKILL.md")
      FileUtils.mkdir_p(stale_agent.dirname)
      FileUtils.mkdir_p(stale_skill.dirname)
      stale_agent.write("stale\n")
      stale_orchestrator.write("stale\n")
      stale_verifier.write("stale\n")
      obsolete_role_agents.each { |path| path.write("obsolete\n") }
      stale_skill.write("stale\n")
      FileUtils.mkdir_p(obsolete_brief_skill.dirname)
      obsolete_brief_skill.write("obsolete\n")
      FileUtils.mkdir_p(obsolete_create_skill.dirname)
      obsolete_create_skill.write("obsolete\n")

      2.times do
        output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
          "--config-home", config_home.to_s)

        assert_predicate status, :success?, error
        assert_includes output, config_home.to_s
      end
      assert_equal %w[kos-brief.md kos-fix.md kos-task.md kos.md], installed_names(config_home.join("commands"))
      assert_equal %w[kos-step-advanced.md kos-step-standard.md], installed_names(config_home.join("agents"))
      assert_equal %w[kos kos-cli kos-git kos-step okf],
        installed_names(config_home.join("skills"))
      refute_predicate stale_agent, :exist?
      refute_predicate stale_orchestrator, :exist?
      refute_predicate stale_verifier, :exist?
      obsolete_role_agents.each { |path| refute_predicate path, :exist? }
      refute_predicate stale_skill, :exist?
      refute_predicate obsolete_brief_skill.dirname, :exist?
      refute_predicate obsolete_create_skill.dirname, :exist?

      assert_matching_tree Rails.root.join(".opencode/commands"), config_home.join("commands")
      assert_matching_tree Rails.root.join(".opencode/agents"), config_home.join("agents")
      assert_matching_tree Rails.root.join("skills"), config_home.join("skills")
    end
  end

  test "refuses symbolic-link OpenCode destinations" do
    Dir.mktmpdir("kos-opencode") do |directory|
      root = Pathname(directory)
      config_home = root.join("config/opencode")
      outside = root.join("outside")
      FileUtils.mkdir_p(config_home)
      FileUtils.mkdir_p(outside)
      outside.join("marker").write("preserved\n")
      FileUtils.ln_s(outside, config_home.join("commands"))

      _output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", config_home.to_s)

      refute_predicate status, :success?
      assert_includes error, "Refusing symbolic-link destination"
      assert_equal "preserved\n", outside.join("marker").read
      refute_predicate config_home.join("agents"), :exist?
    end
  end

  test "fails instead of nesting a skill when replacement cannot be removed" do
    Dir.mktmpdir("kos-opencode") do |directory|
      config_home = Pathname(directory).join("config/opencode")
      skills_directory = config_home.join("skills")
      installed_skill = skills_directory.join("kos")
      FileUtils.mkdir_p(installed_skill)
      FileUtils.chmod(0o555, skills_directory)

      _output, _error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", config_home.to_s)

      refute_predicate status, :success?
      refute_predicate installed_skill.join("kos"), :exist?
    ensure
      FileUtils.chmod(0o755, skills_directory) if skills_directory&.exist?
    end
  end

  private

  def with_installed_cli
    Dir.mktmpdir("kos-installed-cli") do |directory|
      root = Pathname(directory)
      package = root.join("kos.gem")
      gem_home = root.join("gem-home")
      bin_dir = root.join("bin")
      _output, error, status = Open3.capture3(RbConfig.ruby, "-S", "gem", "build", "kos.gemspec",
        "--output", package.to_s, chdir: Rails.root.to_s)
      assert_predicate status, :success?, error
      _output, error, status = Open3.capture3(RbConfig.ruby, "-S", "gem", "install", package.to_s,
        "--install-dir", gem_home.to_s, "--bindir", bin_dir.to_s, "--no-document")
      assert_predicate status, :success?, error
      environment = {
        "BUNDLE_GEMFILE" => nil, "GEM_HOME" => gem_home.to_s, "GEM_PATH" => gem_home.to_s,
        "RUBYGEMS_GEMDEPS" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil
      }
      yield bin_dir.join("kos"), environment, root
    end
  end

  def run_installed_json(cli, environment, root, *arguments)
    output, error, status = Open3.capture3(environment, cli.to_s, *arguments, chdir: root.to_s)
    assert_predicate status, :success?, "#{arguments.join(" ")} failed:\n#{output}#{error}"
    JSON.parse(output)
  end

  def server_environment(system)
    {
      "RAILS_ENV" => "development", "KOS_API_TOKEN" => system.fetch(:token),
      "KOS_DATA_HOME" => system.fetch(:data_home).to_s, "RAILS_LOG_TO_STDOUT" => "1", "DATABASE_URL" => nil
    }
  end

  def start_server(system)
    3.times do
      system[:port] = available_port
      system[:api_url] = "http://127.0.0.1:#{system.fetch(:port)}"
      system[:pid] = Process.spawn(server_environment(system), Rails.root.join("bin/rails").to_s, "server",
        "--binding", "127.0.0.1", "--port", system.fetch(:port).to_s,
        "--pid", system.fetch(:data_home).join("server.pid").to_s,
        out: system.fetch(:log).to_s, err: system.fetch(:log).to_s, pgroup: true)
      started = Timeout.timeout(15) do
        loop do
          if Process.waitpid(system.fetch(:pid), Process::WNOHANG)
            system[:pid] = nil
            break false
          end
          response = Net::HTTP.start("127.0.0.1", system.fetch(:port), open_timeout: 0.2, read_timeout: 0.2) do |http|
            http.get("/up")
          end
          break true if response.is_a?(Net::HTTPSuccess)
        rescue Errno::ECONNREFUSED, EOFError, Net::OpenTimeout, Net::ReadTimeout
          sleep 0.05
        end
      end
      return if started
    end
    flunk("Rails server exited before binding:\n#{system.fetch(:log).read}")
  rescue Timeout::Error
    flunk("Rails server did not start:\n#{system.fetch(:log).read}")
  end

  def stop_server(system)
    return unless system[:pid]

    Process.kill("TERM", -system.fetch(:pid))
    Timeout.timeout(10) { Process.wait(system.fetch(:pid)) }
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  rescue Timeout::Error
    Process.kill("KILL", -system.fetch(:pid))
    Process.wait(system.fetch(:pid))
  ensure
    system[:pid] = nil
  end

  def available_port
    server = TCPServer.new("127.0.0.1", 0)
    server.local_address.ip_port
  ensure
    server&.close
  end

  def installed_names(directory)
    directory.children.map { |path| path.basename.to_s }.sort
  end

  def assert_matching_tree(source, destination)
    source_files = source.glob("**/*").select(&:file?).map { |path| path.relative_path_from(source).to_s }.sort
    destination_files = destination.glob("**/*").select(&:file?).map do |path|
      path.relative_path_from(destination).to_s
    end.sort

    assert_equal source_files, destination_files
    source_files.each do |relative_path|
      assert_equal source.join(relative_path).binread, destination.join(relative_path).binread
    end
  end
end
