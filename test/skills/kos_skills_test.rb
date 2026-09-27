require "test_helper"
require "digest"
require "json"
require "open3"
require "rbconfig"
require "yaml"

class KosSkillsTest < ActiveSupport::TestCase
  SCHEDULER_PATH = Rails.root.join("skills/kos/SKILL.md")
  STEP_PATH = Rails.root.join("skills/kos-step/SKILL.md")
  CLI_PATH = Rails.root.join("skills/kos-cli/SKILL.md")
  AGENT_PATHS = %w[advanced standard].to_h do |tier|
    [ tier, Rails.root.join(".opencode/agents/kos-step-#{tier}.md") ]
  end.freeze
  FORMER_ROLES = %w[diagnose plan implement document brief review publish].freeze

  test "defines discoverable scheduler step and CLI skills without a brief wrapper" do
    assert_skill SCHEDULER_PATH, "kos", /scheduler/
    assert_skill STEP_PATH, "kos-step", /positive task ID/
    assert_skill CLI_PATH, "kos-cli", /public KOS CLI/
    refute_predicate Rails.root.join("skills/kos-brief"), :exist?

    config = JSON.parse(File.read(Rails.root.join("opencode.json")))
    assert_equal [ "./skills" ], config.dig("skills", "paths")
  end

  test "request creation uses the focused idempotent CLI operation" do
    scheduler = File.read(SCHEDULER_PATH)
    compact = scheduler.gsub(/\s+/, " ")

    assert_includes scheduler, "`fix` or `brief`: use `task create-or-get`"
    assert_includes scheduler, "complete exact `$ARGUMENTS` expansion through standard input"
    assert_includes compact, "Follow `kos-cli` whenever a mutation's result is ambiguous"
    %w[intent.json task.json create.lock fsync inode].each { |detail| assert_not_includes scheduler, detail }
  end

  test "slash commands contain only argument handling model choice and shared scheduler entry" do
    commands = {
      "kos" => [ "openai/gpt-5.6-terra", "`development` mode" ],
      "kos-fix" => [ "openai/gpt-5.6-terra", "`fix` mode" ],
      "kos-brief" => [ "openai/gpt-5.6-sol", "`brief` mode" ]
    }

    commands.each do |name, (model, mode)|
      path = Rails.root.join(".opencode/commands/#{name}.md")
      source = File.read(path)
      metadata = frontmatter(path)
      body = source.sub(/\A---\n.*?\n---\n/m, "")

      assert_equal "build", metadata.fetch("agent")
      assert_equal model, metadata.fetch("model")
      assert_includes source, "`kos` scheduler skill"
      assert_includes source, mode
      assert_equal 1, source.scan("$ARGUMENTS").length
      if name != "kos"
        assert_includes source, "exactly one framing newline"
        assert_includes source, "are not request data"
        assert_includes source, "Never infer or unescape the originating argv"
      end
      refute_match(/task (?:context|claim|resume|create-or-get)|owner|profile|outcome/i, body)
      assert_operator body.lines.length, :<=, 8
    end
  end

  test "post-expansion command framing and scheduler stdin preserve exact bytes" do
    cases = [
      [ "kos-fix", "kos-fix", "\"ORDINARY MULTIWORD 015\"",
        "request:fix:sha256:7a41176a1495af8b69226d93393c24567c250ad7772a2e925681a9e8724971fa" ],
      [ "kos-brief", "kos-brief", "ORDINARY MULTIWORD 015",
        "request:brief:sha256:64edabdfb7b92d3aea3c36a643d50b4a358c9594975975f041b3a95c6d2258dc" ],
      [ "kos-fix", "kos-fix", '"display literal \"ready\" 015"',
        "request:fix:sha256:9ae544702eef4696dd74f3341c547cff574d2b933bbfdd13d10780c807e7963f" ],
      [ "kos-brief", "kos-brief", "\"\n BOUNDARY_WHITESPACE_015 \n\"",
        "request:brief:sha256:1c0cc34baf2e9ffeee149ab61376bd07c1dc8d8e4aa8e1bf67a8bdf5fe6f59ed" ]
    ]

    cases.each do |command, tag, expected_request, expected_key|
      template = File.read(Rails.root.join(".opencode/commands/#{command}.md"))
      expanded = template.sub("$ARGUMENTS", expected_request)
      opening = "<#{tag}-arguments>\n"
      closing = "\n</#{tag}-arguments>"
      argument_start = expanded.index(opening) + opening.bytesize
      argument_end = expanded.index(closing, argument_start)
      scheduler_request = expanded.byteslice(argument_start...argument_end)
      cli_arguments = [ "task", "create-or-get", "--project-id", "1", "--kind", command.delete_prefix("kos-"),
        "--owner-id", "session", "--request-file", "-" ]
      output, error, status = Open3.capture3({ "RUBYOPT" => nil, "RUBYLIB" => nil }, RbConfig.ruby,
        "--disable-gems", Rails.root.join("test/support/capture_cli_stdin.rb").to_s, *cli_arguments,
        stdin_data: scheduler_request)
      captured = JSON.parse(output)

      assert_predicate status, :success?
      assert_empty error
      assert_equal cli_arguments, captured.fetch("arguments")
      assert_equal expected_request.b, [ captured.fetch("stdin_hex") ].pack("H*").b
      kind = command.delete_prefix("kos-")
      assert_equal expected_key, "request:#{kind}:sha256:#{Digest::SHA256.hexdigest(scheduler_request)}"
    end
  end

  test "documents the OpenCode 1.18.26 argv serialization boundary" do
    readme = File.read(Rails.root.join("README.md"))

    assert_includes readme, "OpenCode 1.18.26 has a CLI serialization\nlimitation"
    assert_includes readme, "opencode run --command kos-fix status is wrong"
    assert_includes readme, "KOS intentionally does not guess, strip wrappers, or unescape"
  end

  test "scheduler dispatches by authoritative mode and tier with an ID-only prompt" do
    source = File.read(SCHEDULER_PATH)
    compact = source.gsub(/\s+/, " ")

    assert_includes source, "`execution_mode` and `model_tier`"
    assert_includes source, "For `main`, load `kos-step`"
    assert_includes source, "execute exactly one step in this command\n   agent"
    assert_includes source, "For `subagent`, launch one fresh foreground `kos-step-standard` or\n   `kos-step-advanced`"
    assert_includes compact, "complete prompt is only the positive decimal task ID"
    assert_includes source, "After either path"
    assert_includes source, "`completed` or `cancelled`"
    assert_includes source, "On `needs_human` or `blocked`"
    assert_includes source, "status, current step, claim version, and accepted"
    assert_includes source, "active for that owner at the same step"
    assert_includes source, "claim\n   version incremented by one and a renewed valid lease"
    assert_includes source, "dispatch that step at most once more"
    FORMER_ROLES.each { |role| assert_not_includes source, "`kos-#{role}`" }
    refute_match(/^\| .* \| .* \|$/, source)
  end

  test "scheduler obtains one private command owner from the CLI" do
    source = File.read(SCHEDULER_PATH)

    assert_includes source, "Run `kos session-id` once"
    assert_includes source, "Never\nask a model to generate randomness"
    assert_includes source, "Never\nask a model to generate randomness, read `KOS_OWNER_ID`, or reuse an owner"
    assert_not_includes source, "<32 lowercase hex digits>"
    assert_not_includes source, "PID"
  end

  test "scheduler phase has no artifact Git or result-parsing policy" do
    source = File.read(SCHEDULER_PATH)

    assert_includes source, "During scheduling"
    assert_includes source, "never add context to a child prompt, inspect artifact bodies or Git"
    assert_includes source, "interpret\nchild output"
    assert_includes source, "report a step"
    assert_includes source, "keep local recovery state"
    assert_not_includes source, "<step-id>.md"
    assert_not_includes source, '"outcome"'
    assert_not_includes source, "git status"
  end

  test "step guidance uses workflow context as the complete role contract" do
    source = File.read(STEP_PATH)

    assert_includes source, "Accept one positive ASCII-decimal task ID"
    assert_includes source, "`execution_mode` and `model_tier`"
    assert_includes source, "In the command agent, require `execution_mode` `main`"
    assert_includes source, "workflow\ninstruction is the complete substantive role and authority contract"
    assert_includes source, "Load `kos-git` with the\ntask ID"
    assert_includes source, "server is authoritative"
    assert_includes source, "observe task state before any retry"
    assert_includes source, "Do not execute the next step"
    assert_includes source, "`task report-attempt` template"
    assert_includes source, "In the command agent, return\ncontrol to the scheduler phase"
    assert_not_includes source, "role-specific"
  end

  test "CLI skill provides frequent templates and retains safety boundaries" do
    source = File.read(CLI_PATH)

    %w[KOS_CLI_PATH KOS_API_URL KOS_API_TOKEN --version --help session-id].each do |contract|
      assert_includes source, contract
    end
    [
      "project show --repository-identity", "task create-or-get", "task resumable", "task claim-next",
      "task resume", "task context", "task artifact", "task report-attempt", "task children",
      "task materialize-children"
    ].each { |template| assert_includes source, template }
    assert_includes source, "Installed per-command help is the fallback"
    assert_match(/standard input|stdin/i, source)
    assert_match(/retry/i, source)
    (0..3).each { |status| assert_match(/Exit `#{status}`/, source) }
  end

  test "installs exactly two generic tier profiles without role policy" do
    assert_equal %w[kos-step-advanced.md kos-step-standard.md],
      Rails.root.join(".opencode/agents").children.map { |path| path.basename.to_s }.sort

    AGENT_PATHS.each do |tier, path|
      profile = frontmatter(path)
      source = File.read(path)
      expected = tier == "standard" ? [ "openai/gpt-5.6-terra", "medium" ] : [ "openai/gpt-5.6-sol", "high" ]

      assert_equal %w[description mode model reasoningEffort], profile.keys.sort
      assert_equal "subagent", profile.fetch("mode")
      assert_equal expected, profile.values_at("model", "reasoningEffort")
      refute profile.key?("permission")
      assert_includes source, "prompt is only the task ID"
      assert_includes source, "`model_tier` `#{tier}`"
      assert_includes source, "workflow step instruction"
      FORMER_ROLES.each { |role| assert_not_includes source, "`#{role}`" }
    end
  end

  test "built-in workflow instructions retain delivery and independent review boundaries" do
    definitions = BuiltInCatalog.definitions
    all_steps = definitions.values.flat_map { |definition| definition.fetch("steps") }
    instructions = all_steps.to_h { |step| [ step.fetch("id"), step.fetch("instruction") ] }
    development = definitions.fetch("development").fetch("steps").index_by { |step| step.fetch("id") }

    assert_includes definitions.dig("fix", "steps").first.fetch("instruction"), "exported temporary copy"
    assert_includes development.dig("implement", "instruction"), "every required test, lint, formatting, build, and type check"
    assert_includes development.dig("implement", "instruction"), "never push"
    assert_includes development.dig("review", "instruction"), "without changing HEAD, refs, index, worktree bytes, or status"
    assert_includes development.dig("review", "instruction"), "nonempty contiguous linear single-parent sequence"
    assert_includes development.dig("review", "instruction"), "exactly one raw line KOS-Task: <task-id>"
    assert_includes development.dig("review", "instruction"), "exact base, ordered commits, tip"
    assert_includes development.dig("publish", "instruction"), "push the exact tip without force"
    assert_includes development.dig("publish", "instruction"), "observing the exact approved sequence remotely"
    brief = definitions.fetch("brief").fetch("steps").index_by { |step| step.fetch("id") }
    assert_includes brief.dig("review", "instruction"), "proposed minimal acyclic graph"
    assert_includes brief.dig("review", "instruction"), "brief_graph"
    assert_includes brief.dig("publish", "instruction"), "graph_digest"
    assert_includes brief.dig("publish", "instruction"), "nonempty contiguous linear single-parent sequence"
    assert_includes brief.dig("publish", "instruction"), "exactly one raw line KOS-Task: <task-id>"
    assert all_steps.all? { |step| step.fetch("instruction").present? }
    assert instructions.key?("publish")
  end

  private

  def assert_skill(path, name, description_pattern)
    source = File.read(path)
    metadata = YAML.safe_load(source.match(/\A---\n(.*?)\n---/m)[1])
    assert_equal name, metadata.fetch("name")
    assert_match description_pattern, metadata.fetch("description")
    assert_equal [ "SKILL.md" ], Dir.children(path.dirname).sort
  end

  def frontmatter(path)
    YAML.safe_load(File.read(path).match(/\A---\n(.*?)\n---/m)[1])
  end
end
