require "test_helper"
require "kos/open_code_installation"
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
      expected_source_id = Kos::BuildIdentity.source_id(root: Rails.root)
      assert_equal "kos #{Kos::VERSION} source=#{expected_source_id}\n", output
      assert_empty error

      claim_id, error, status = Open3.capture3(environment.merge("KOS_API_URL" => "invalid"),
        bin_dir.join("kos").to_s, "claim-id", chdir: directory)
      assert_predicate status, :success?, error
      assert_match(/\Akos-claim-[0-9a-f]{32}\n\z/, claim_id)
      assert_empty error

      output, error, status = Open3.capture3(environment, bin_dir.join("kos").to_s, "--help", chdir: directory)
      assert_predicate status, :success?, error
      assert_match(/^\s*health\s*$/, output)
      assert_match(/^\s*status\s*$/, output)
      {
        "project" => %w[create show resolve update],
        "workflow" => %w[create list show schema],
        "plan" => %w[put list show abandon],
        "task" => %w[list ready show context result claim takeover report answer]
      }.each do |resource, actions|
        inventory = output.lines.grep(/^\s*#{Regexp.escape(resource)}\s+/).join
        assert_not_empty inventory
        actions.each { |action| assert_match(/\b#{Regexp.escape(action)}\b/, inventory) }
      end

      {
        %w[project resolve] => %w[--remote],
        %w[status] => %w[--remote],
        %w[workflow create] => %w[--key --name --definition-file complete_task needs_human],
        %w[workflow list] => %w[--key],
        %w[workflow show] => [],
        %w[workflow schema] => [],
        %w[task context] => [],
        %w[plan abandon] => %w[--project-id --key --version],
        %w[task result] => %w[--step],
        %w[task report] => %w[--claim-id --version --result-file]
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
      system = { data_home: root.join("data"), token: "smoke secret._~+/=", log: root.join("server.log") }
      _output, error, status = Open3.capture3(server_environment(system), Rails.root.join("bin/rails").to_s,
        "db:prepare")
      assert_predicate status, :success?, error
      _output, error, status = Open3.capture3(server_environment(system), Rails.root.join("bin/rails").to_s,
        "db:seed")
      assert_predicate status, :success?, error

      start_server(system)
      environment = cli_environment.merge("KOS_API_URL" => system.fetch(:api_url))
      output, error, status = Open3.capture3(environment, cli.to_s, "health", chdir: root.to_s)
      assert_predicate status, :success?, error
      assert_not_empty output

      ready = JSON.parse(Net::HTTP.get(URI("#{system.fetch(:api_url)}/ready")))
      assert_equal "ready", ready.fetch("status")
      assert_equal Kos::BuildIdentity.source_id(root: Rails.root), ready.fetch("source_id")

      database = system.fetch(:data_home).join("production.sqlite3")
      _output, error, status = Open3.capture3("sqlite3", database.to_s,
        "UPDATE workflows SET key = 'development-unavailable' WHERE key = 'development';")
      assert_predicate status, :success?, error
      uri = URI("#{system.fetch(:api_url)}/ready")
      request = Net::HTTP::Get.new(uri)
      request["X-Request-Id"] = "operations-smoke-request"
      request["Authorization"] = "Bearer #{system.fetch(:token)}"
      unavailable = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
      assert_equal "503", unavailable.code
      _output, error, status = Open3.capture3("sqlite3", database.to_s,
        "UPDATE workflows SET key = 'development' WHERE key = 'development-unavailable';")
      assert_predicate status, :success?, error
      Timeout.timeout(2) do
        sleep 0.05 until system.fetch(:log).read.include?("operations-smoke-request")
      end
      log = system.fetch(:log).read
      assert_includes log, "KOS readiness failed"
      assert_includes log, "operations-smoke-request"
      refute_includes log, system.fetch(:token)

      authenticated = environment.merge("KOS_API_TOKEN" => system.fetch(:token))
      workflows = run_installed_json(cli, authenticated, root, "workflow", "list").fetch("workflows")
      development = workflows.find { |workflow| workflow.fetch("key") == "development" }
      shown_workflow = run_installed_json(cli, authenticated, root, "workflow", "show",
        development.fetch("id").to_s).fetch("workflow")
      assert_equal development, shown_workflow
      workflow_contract = run_installed_json(cli, authenticated, root, "workflow", "schema")
      assert_equal %w[steps], workflow_contract.dig("schema", "required_fields")
      assert_not_empty workflow_contract.dig("example", "steps")
      Tempfile.create([ "custom-workflow", ".json" ], root.to_s) do |workflow_file|
        workflow_file.write(JSON.generate(workflow_contract.fetch("example")))
        workflow_file.flush
        custom = run_installed_json(cli, authenticated, root, "workflow", "create", "--key", "custom-smoke",
          "--name", "Custom smoke", "--definition-file", workflow_file.path).fetch("workflow")
        assert_equal [ "custom-smoke", 1 ], custom.values_at("key", "revision")
      end

      project = run_installed_json(cli, authenticated, root, "project", "create", "--name", "Smoke",
        "--remote-url", "https://example.test/test/smoke.git", "--default-branch", "main").fetch("project")
      _output, error, status = Open3.capture3("git", "-C", root.to_s, "init", "--quiet")
      assert_predicate status, :success?, error
      _output, error, status = Open3.capture3("git", "-C", root.to_s, "remote", "add", "recovery",
        "https://example.test/test/smoke.git")
      assert_predicate status, :success?, error
      resolved = run_installed_json(cli, authenticated, root, "project", "resolve", "--remote", "recovery")
        .fetch("project")
      assert_equal project.fetch("id"), resolved.fetch("id")
      shown = run_installed_json(cli, authenticated, root, "project", "show", "--repository-identity",
        "example.test/test/smoke").fetch("project")
      assert_equal project.fetch("id"), shown.fetch("id")

      task = nil
      paused_task = nil
      active_task = nil
      blocked_task = nil
      Tempfile.create([ "smoke-plan", ".json" ], root.to_s) do |plan_file|
        plan_file.write(JSON.generate(key: "smoke", title: "Smoke", tasks: [
          {
            key: "lifecycle", title: "Smoke lifecycle", description_markdown: "Run the lifecycle",
            workflow_key: "development", blocker_keys: []
          },
          {
            key: "paused", title: "Smoke pause", description_markdown: "Pause the lifecycle",
            workflow_key: "development", blocker_keys: []
          },
          {
            key: "active", title: "Smoke active claim", description_markdown: "Keep the claim active",
            workflow_key: "development", blocker_keys: []
          },
          {
            key: "blocked", title: "Smoke obstruction", description_markdown: "Block the lifecycle",
            workflow_key: "development", blocker_keys: []
          }
        ]))
        plan_file.flush
        run_installed_json(cli, authenticated, root, "plan", "put", "--project-id", project.fetch("id").to_s,
          "--definition-file", plan_file.path)
        task = run_installed_json(cli, authenticated, root, "task", "ready", "--project-id",
          project.fetch("id").to_s).fetch("tasks").first

        Tempfile.create([ "smoke-result", ".md" ], root.to_s) do |result_file|
          result_file.write("# Result\n")
          result_file.flush
          { "plan" => "planned", "implement" => "implemented", "review" => "approved",
            "publish" => "published" }.each_with_index do |(step, outcome), index|
            claim_id = "smoke-#{index}"
            task = run_installed_json(cli, authenticated, root, "task", "claim", task.fetch("id").to_s,
              "--claim-id", claim_id, "--version", task.fetch("version").to_s).fetch("task")
            task = run_installed_json(cli, authenticated, root, "task", "report", task.fetch("id").to_s,
              "--claim-id", claim_id, "--version", task.fetch("version").to_s, "--step", step,
              "--outcome", outcome, "--result-file", result_file.path).fetch("task")
          end

          context = run_installed_json(cli, authenticated, root, "task", "context", task.fetch("id").to_s)
          assert_equal [ "completed", "publish", nil ],
            context.fetch("task").values_at("status", "current_step", "claim_id")
          assert_equal %w[plan implement review publish], context.fetch("results").map { |entry| entry.fetch("step") }

          paused_task = run_installed_json(cli, authenticated, root, "task", "ready", "--project-id",
            project.fetch("id").to_s).fetch("tasks").first
          paused_task = run_installed_json(cli, authenticated, root, "task", "claim", paused_task.fetch("id").to_s,
            "--claim-id", "smoke-pause", "--version", paused_task.fetch("version").to_s).fetch("task")
          paused_task = run_installed_json(cli, authenticated, root, "task", "report", paused_task.fetch("id").to_s,
            "--claim-id", "smoke-pause", "--version", paused_task.fetch("version").to_s, "--step", "plan",
            "--outcome", "needs_human", "--result-file", result_file.path, "--message", "Choose a direction").fetch("task")
          paused_task = run_installed_json(cli, authenticated, root, "task", "answer", paused_task.fetch("id").to_s,
            "--version", paused_task.fetch("version").to_s, "--step", "plan", "--answer-file", result_file.path).fetch("task")

          active_task = run_installed_json(cli, authenticated, root, "task", "ready", "--project-id",
            project.fetch("id").to_s).fetch("tasks").find { |candidate| candidate.fetch("key") == "active" }
          active_task = run_installed_json(cli, authenticated, root, "task", "claim", active_task.fetch("id").to_s,
            "--claim-id", "smoke-active", "--version", active_task.fetch("version").to_s).fetch("task")

          blocked_task = run_installed_json(cli, authenticated, root, "task", "ready", "--project-id",
            project.fetch("id").to_s).fetch("tasks").find { |candidate| candidate.fetch("key") == "blocked" }
          blocked_task = run_installed_json(cli, authenticated, root, "task", "claim", blocked_task.fetch("id").to_s,
            "--claim-id", "smoke-blocked", "--version", blocked_task.fetch("version").to_s).fetch("task")
          blocked_task = run_installed_json(cli, authenticated, root, "task", "report", blocked_task.fetch("id").to_s,
            "--claim-id", "smoke-blocked", "--version", blocked_task.fetch("version").to_s, "--step", "plan",
            "--outcome", "blocked", "--result-file", result_file.path, "--message",
            "Dependency unavailable").fetch("task")
        end
      end

      current_plan = run_installed_json(cli, authenticated, root, "plan", "show", "--project-id",
        project.fetch("id").to_s, "--key", "smoke").fetch("task_plan")
      abandoned_plan = run_installed_json(cli, authenticated, root, "plan", "abandon", "--project-id",
        project.fetch("id").to_s, "--key", "smoke", "--version", current_plan.fetch("version").to_s)
      assert_equal "abandoned", abandoned_plan.dig("task_plan", "status")
      assert_equal [ "completed", "abandoned", "abandoned", "abandoned" ],
        abandoned_plan.fetch("tasks").pluck("status")

      stop_server(system)
      backup = root.join("production-backup.sqlite3")
      _output, error, status = Open3.capture3("sqlite3", database.to_s, ".backup '#{backup}'")
      assert_predicate status, :success?, error
      integrity, error, status = Open3.capture3("sqlite3", backup.to_s, "PRAGMA integrity_check;")
      assert_predicate status, :success?, error
      assert_equal "ok\n", integrity
      foreign_keys, error, status = Open3.capture3("sqlite3", backup.to_s, "PRAGMA foreign_key_check;")
      assert_predicate status, :success?, error
      assert_empty foreign_keys

      restored_home = root.join("restored-data")
      restored_home.mkpath
      FileUtils.cp(backup, restored_home.join("production.sqlite3"))
      system = { data_home: restored_home, token: system.fetch(:token), log: root.join("restored-server.log") }
      start_server(system)
      restored_ready = JSON.parse(Net::HTTP.get(URI("#{system.fetch(:api_url)}/ready")))
      assert_equal "ready", restored_ready.fetch("status")
      restored_environment = cli_environment.merge("KOS_API_URL" => system.fetch(:api_url),
        "KOS_API_TOKEN" => system.fetch(:token))
      recovery_status = run_installed_json(cli, restored_environment, root, "status", "--remote", "recovery")
      restored = recovery_status.fetch("project")
      assert_equal project.fetch("id"), restored.fetch("id")
      discovered_plans = recovery_status.fetch("task_plans")
      assert_equal [ "smoke" ], discovered_plans.pluck("key")
      assert_equal "abandoned", discovered_plans.first.fetch("status")
      discovered_tasks = recovery_status.fetch("tasks")
      assert_equal %w[paused active blocked], discovered_tasks.pluck("key")
      assert_equal [ "abandoned", "plan", "Choose a direction", "# Result\n" ],
        discovered_tasks.first.values_at("status", "pause_step", "pause_message", "answer")
      assert_equal [ "abandoned", nil, 2 ],
        discovered_tasks.second.values_at("status", "claim_id", "version")
      assert_equal [ "abandoned", "blocked", "plan", "Dependency unavailable", nil ],
        discovered_tasks.last.values_at("status", "pause_kind", "pause_step", "pause_message", "answer")
      all_tasks = run_installed_json(cli, restored_environment, root, "task", "list", "--project-id",
        restored.fetch("id").to_s, "--include-completed").fetch("tasks")
      assert_equal %w[lifecycle paused active blocked], all_tasks.pluck("key")
      restored_context = run_installed_json(cli, restored_environment, root, "task", "context",
        task.fetch("id").to_s)
      assert_equal "completed", restored_context.dig("task", "status")
      assert_equal %w[plan implement review publish], restored_context.fetch("results").map { |entry| entry.fetch("step") }
      restored_pause = run_installed_json(cli, restored_environment, root, "task", "context",
        paused_task.fetch("id").to_s)
      assert_equal [ "abandoned", "plan", "# Result\n" ],
        [ restored_pause.dig("task", "status"), restored_pause.dig("pause", "step"),
          restored_pause.dig("pause", "answer") ]
      restored_active = run_installed_json(cli, restored_environment, root, "task", "context",
        active_task.fetch("id").to_s)
      assert_equal [ "abandoned", nil, 2 ],
        restored_active.fetch("task").values_at("status", "claim_id", "version")
      assert_empty run_installed_json(cli, restored_environment, root, "task", "ready", "--project-id",
        restored.fetch("id").to_s).fetch("tasks")
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
      obsolete_git_skill = config_home.join("skills/kos-git/SKILL.md")
      obsolete_step_skill = config_home.join("skills/kos-step/SKILL.md")
      obsolete_commands = %w[kos-brief.md kos-fix.md kos-task.md].map { |name| config_home.join("commands", name) }
      obsolete_tier_agents = %w[kos-step-advanced.md kos-step-standard.md].map { |name| config_home.join("agents", name) }
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
      FileUtils.mkdir_p(obsolete_git_skill.dirname)
      obsolete_git_skill.write("obsolete\n")
      FileUtils.mkdir_p(obsolete_step_skill.dirname)
      obsolete_step_skill.write("obsolete\n")
      FileUtils.mkdir_p(config_home.join("commands"))
      obsolete_commands.each { |path| path.write("obsolete\n") }
      obsolete_tier_agents.each { |path| path.write("obsolete\n") }

      2.times do
        output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
          "--config-home", config_home.to_s)

        assert_predicate status, :success?, error
        assert_includes output, config_home.to_s
        assert_includes output, "Fully restart OpenCode"
        assert_includes output, "installation check"
      end
      manifest = JSON.parse(config_home.join("kos-installation.json").read)
      assert_equal Kos::OpenCodeInstallation::SCHEMA, manifest.fetch("schema")
      assert_equal Kos::VERSION, manifest.fetch("version")
      assert_equal Kos::BuildIdentity.source_id(root: Rails.root), manifest.fetch("source_id")
      assert_equal %w[kos.md], manifest.fetch("commands")
      assert_equal %w[kos-worker.md], manifest.fetch("agents")
      assert_equal %w[kos kos-cli kos-worker okf], manifest.fetch("skills")
      assert_equal %w[kos.md], installed_names(config_home.join("commands"))
      assert_equal %w[kos-worker.md], installed_names(config_home.join("agents"))
      assert_equal %w[kos kos-cli kos-worker okf],
        installed_names(config_home.join("skills"))
      refute_predicate stale_agent, :exist?
      refute_predicate stale_orchestrator, :exist?
      refute_predicate stale_verifier, :exist?
      obsolete_role_agents.each { |path| refute_predicate path, :exist? }
      refute_predicate stale_skill, :exist?
      refute_predicate obsolete_brief_skill.dirname, :exist?
      refute_predicate obsolete_create_skill.dirname, :exist?
      refute_predicate obsolete_git_skill.dirname, :exist?
      refute_predicate obsolete_step_skill.dirname, :exist?
      obsolete_commands.each { |path| refute_predicate path, :exist? }
      obsolete_tier_agents.each { |path| refute_predicate path, :exist? }

      assert_matching_tree Rails.root.join(".opencode/commands"), config_home.join("commands")
      assert_matching_tree Rails.root.join(".opencode/agents"), config_home.join("agents")
      assert_matching_tree Rails.root.join("skills"), config_home.join("skills")
    end
  end

  test "removes assets owned by a prior manifest and preserves unmanaged OpenCode files" do
    Dir.mktmpdir("kos-opencode") do |directory|
      config_home = Pathname(directory).join("config/opencode")
      stale_command = config_home.join("commands/kos-old.md")
      stale_agent = config_home.join("agents/kos-old.md")
      stale_skill = config_home.join("skills/kos-old/SKILL.md")
      user_command = config_home.join("commands/user-command.md")
      reserved_user_command = config_home.join("commands/kos-fix.md")
      user_agent = config_home.join("agents/user-agent.md")
      user_skill = config_home.join("skills/user-skill/SKILL.md")
      [ stale_command, stale_agent, stale_skill, user_command, reserved_user_command, user_agent, user_skill ].each do |path|
        FileUtils.mkdir_p(path.dirname)
        path.write("preserved unless managed\n")
      end
      config_home.join("kos-installation.json").write(JSON.generate({
        schema: Kos::OpenCodeInstallation::SCHEMA,
        version: "0.0.1",
        source_id: "sha256:#{"0" * 64}",
        commands: %w[kos.md kos-old.md],
        agents: %w[kos-worker.md kos-old.md],
        skills: %w[kos kos-cli kos-worker okf kos-old]
      }))

      _output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", config_home.to_s)

      assert_predicate status, :success?, error
      [ stale_command, stale_agent, stale_skill.dirname ].each { |path| refute_predicate path, :exist? }
      [ user_command, reserved_user_command, user_agent, user_skill ].each { |path| assert_predicate path, :file? }
      assert_predicate config_home.join("commands/kos.md"), :file?
      assert_predicate config_home.join("agents/kos-worker.md"), :file?
      assert_predicate config_home.join("skills/kos/SKILL.md"), :file?
    end
  end

  test "rejects an invalid prior manifest before changing OpenCode files" do
    Dir.mktmpdir("kos-opencode") do |directory|
      root = Pathname(directory)
      config_home = root.join("config/opencode")
      FileUtils.mkdir_p(config_home.join("commands"))
      config_home.join("commands/user-command.md").write("user\n")
      config_home.join("kos-installation.json").write("{invalid")
      before = tree_snapshot(root)

      _output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", config_home.to_s)

      refute_predicate status, :success?
      assert_includes error, "No files were changed"
      assert_equal before, tree_snapshot(root)
    end
  end

  test "rejects unowned current destinations and non-KOS manifest claims before changing files" do
    Dir.mktmpdir("kos-opencode") do |directory|
      root = Pathname(directory)
      config_home = root.join("config/opencode")
      FileUtils.mkdir_p(config_home.join("commands"))
      config_home.join("commands/kos.md").write("user collision\n")
      manifest = {
        schema: Kos::OpenCodeInstallation::SCHEMA,
        version: "0.0.1",
        source_id: "sha256:#{"0" * 64}",
        commands: [],
        agents: [],
        skills: []
      }
      config_home.join("kos-installation.json").write(JSON.generate(manifest))
      before = tree_snapshot(root)

      _output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", config_home.to_s)

      refute_predicate status, :success?
      assert_includes error, "unowned destination"
      assert_equal before, tree_snapshot(root)

      FileUtils.rm_f(config_home.join("commands/kos.md"))
      manifest[:commands] = %w[user-command.md]
      config_home.join("kos-installation.json").write(JSON.generate(manifest))
      before = tree_snapshot(root)
      _output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", config_home.to_s)

      refute_predicate status, :success?
      assert_includes error, "KOS-managed names"
      assert_equal before, tree_snapshot(root)
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

  test "rejects a relative explicit OpenCode destination without changing files" do
    Dir.mktmpdir("kos-opencode") do |directory|
      root = Pathname(directory)
      config_home = root.join("config/opencode")
      FileUtils.mkdir_p(config_home)
      config_home.join("marker").write("preserved\n")
      before = tree_snapshot(root)

      _output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", "config/opencode", chdir: root.to_s)

      refute_predicate status, :success?
      assert_includes error, "--config-home must be an absolute path"
      assert_equal before, tree_snapshot(root)
    end
  end

  test "ignores a relative XDG configuration home" do
    Dir.mktmpdir("kos-opencode") do |directory|
      root = Pathname(directory)
      home = root.join("home")
      home.mkpath

      _output, error, status = Open3.capture3(
        { "HOME" => home.to_s, "XDG_CONFIG_HOME" => "relative-config" },
        Rails.root.join("bin/install-opencode").to_s,
        chdir: root.to_s
      )

      assert_predicate status, :success?, error
      assert_predicate home.join(".config/opencode/kos-installation.json"), :file?
      refute_predicate root.join("relative-config"), :exist?
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
      "RAILS_ENV" => "production", "KOS_API_TOKEN" => system.fetch(:token),
      "KOS_DATA_HOME" => system.fetch(:data_home).to_s, "SECRET_KEY_BASE" => "production-smoke-secret",
      "DATABASE_URL" => nil
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

  def tree_snapshot(root)
    root.glob("**/*", File::FNM_DOTMATCH).filter_map do |path|
      next if %w[. ..].include?(path.basename.to_s)

      value = path.directory? ? :directory : path.binread
      [ path.relative_path_from(root).to_s, value ]
    end.sort_by(&:first)
  end
end
