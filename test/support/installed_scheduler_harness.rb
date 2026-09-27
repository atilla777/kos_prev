require "open3"
require "tmpdir"
require "yaml"
require_relative "kos_scheduler_harness"

class InstalledSchedulerHarness
  MODES = %w[development fix brief custom].freeze

  def self.install
    Dir.mktmpdir("kos-scheduler-opencode") do |directory|
      config_home = Pathname(directory).join("opencode")
      _output, error, status = Open3.capture3(Rails.root.join("bin/install-opencode").to_s,
        "--config-home", config_home.to_s)
      raise "OpenCode installation failed: #{error}" unless status.success?

      yield config_home
    end
  end

  def initialize(config_home:, cli:, main_runner:, subagent_runner:, clock: -> { Time.now.utc })
    @config_home = config_home
    @cli = cli
    @main_runner = main_runner
    @subagent_runner = subagent_runner
    @clock = clock
  end

  def run(command:, project_id:, arguments: "", answer: nil)
    command_metadata, mode = installed_command(command)
    owner_id = @cli.session_id
    scheduler = KosSchedulerHarness.new(cli: @cli,
      main_runner: lambda { |task_id|
        load_skill("kos-step")
        load_skill("okf") if command == "kos-brief"
        @main_runner.call(task_id, owner_id:, command:, model: command_metadata.fetch("model"))
      },
      subagent_runner: lambda { |tier:, prompt:|
        profile = frontmatter(@config_home.join("agents/kos-step-#{tier}.md"))
        raise "wrong installed profile" unless profile.fetch("mode") == "subagent"

        @subagent_runner.call(tier:, prompt:, owner_id:, profile: "kos-step-#{tier}", model: profile.fetch("model"))
      }, clock: @clock)

    return scheduler.run_custom(project_id:, task_type_key: arguments, owner_id:, answer:) if mode == "custom"

    selected = if mode == "development"
      @cli.resumable(project_id:, task_type_key: mode).first ||
        @cli.claim_next(project_id:, task_type_key: mode, owner_id:)
    else
      @cli.create_or_get(project_id:, kind: mode, request: arguments, owner_id:)
    end
    return KosSchedulerHarness::Result.new(reason: "unavailable", state: nil) unless selected

    task = selected.fetch("task")
    if task.fetch("status") == "needs_human" && answer
      @cli.resume(task_id: task.fetch("id"), owner_id:, claim_version: task.fetch("claim_version"),
        step: task.fetch("current_step"), answer:)
    end
    scheduler.run(task_id: task.fetch("id"), owner_id:)
  end

  private

  def installed_command(command)
    %w[kos kos-cli kos-git].each { |skill| load_skill(skill) }
    path = @config_home.join("commands/#{command}.md")
    source = path.read
    mode = source.match(/`kos` scheduler skill in\s+`(\w+)` mode/m)&.captures&.first
    raise "invalid installed scheduler command" unless MODES.include?(mode)

    [ frontmatter(path), mode ]
  end

  def load_skill(name)
    path = @config_home.join("skills/#{name}/SKILL.md")
    metadata = frontmatter(path)
    raise "wrong installed skill" unless metadata.fetch("name") == name

    metadata
  end

  def frontmatter(path)
    source = path.read
    YAML.safe_load(source.match(/\A---\n(.*?)\n---/m)[1])
  end
end
