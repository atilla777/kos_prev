require "test_helper"
require "json"
require "yaml"

class KosSkillsTest < ActiveSupport::TestCase
  SKILLS = %w[kos kos-cli kos-worker okf].freeze

  test "ships only the focused managed command agent and skills" do
    assert_equal [ "kos.md" ], managed_names(".opencode/commands")
    assert_equal [ "kos-worker.md" ], managed_names(".opencode/agents")
    assert_equal SKILLS, managed_names("skills")

    SKILLS.each do |name|
      path = Rails.root.join("skills", name, "SKILL.md")
      metadata = frontmatter(path)
      assert_equal name, metadata.fetch("name")
      assert metadata.fetch("description").present?
      assert_equal [ "SKILL.md" ], Dir.children(path.dirname).sort
    end
  end

  test "command enters the orchestrator with the complete goal" do
    path = Rails.root.join(".opencode/commands/kos.md")
    source = File.read(path)
    metadata = frontmatter(path)

    assert_equal "build", metadata.fetch("agent")
    assert_equal "openai/gpt-5.6-sol", metadata.fetch("model")
    assert_includes source, "Load the `kos` skill"
    assert_equal 1, source.scan("$ARGUMENTS").length
    assert_includes source, "<kos-goal>"
    refute_match(/development mode|resume|session-id|kos-step/, source)
  end

  test "orchestrator coordinates but never performs substantive work" do
    source = File.read(Rails.root.join("skills/kos/SKILL.md"))

    assert_includes source, "store it atomically"
    assert_includes source, "Dispatch independent claims in\nparallel"
    assert_includes source, "`task_id`, `claim_id`, `version`, and `step`"
    assert_includes source, "It never performs a\nworkflow step"
    assert_includes source, "trust KOS state rather than worker prose"
    assert_includes source, "discover\nunfinished plans and tasks"
    assert_includes source, "before creating replacement work"
    assert_includes source, "Take over an active task only after deciding its worker has\nstopped"
    refute_match(/git status|git push|retry|lease|review algorithm/i, source)
  end

  test "worker executes exactly one immutable fenced step" do
    skill = File.read(Rails.root.join("skills/kos-worker/SKILL.md"))
    agent_path = Rails.root.join(".opencode/agents/kos-worker.md")
    agent = File.read(agent_path)
    metadata = frontmatter(agent_path)

    assert_equal "subagent", metadata.fetch("mode")
    assert_equal %w[description mode model reasoningEffort], metadata.keys.sort
    assert_includes agent, "immutable JSON envelope"
    assert_includes skill, "require\nall four values to match"
    assert_includes skill, "original\nenvelope's `claim_id`, `version`, and `step`"
    assert_includes skill, "Never adopt a later claim, version, or\nstep"
    assert_includes skill, "never execute the next step"
    assert_includes skill, "workflow instruction defines the single step's objective and authority"
    refute_match(/git (?:status|diff|push|commit)|retry|lock|lease/i, skill)
  end

  test "CLI skill is concise and names the complete public surface" do
    source = File.read(Rails.root.join("skills/kos-cli/SKILL.md"))

    %w[KOS_CLI_PATH KOS_API_URL KOS_API_TOKEN health claim-id].each { |value| assert_includes source, value }
    [ "project create/show/update", "workflow create", "plan\nput/list/show",
      "task list/ready/show/context/result/claim/takeover/report/answer" ].each do |surface|
      assert_includes source, surface
    end
    assert_includes source, "Pass each value as a separate argument"
    assert_includes source, "use `-` for standard input"
    (0..3).each { |status| assert_includes source, "`#{status}`" }
    refute_match(/session-id|task-type|resume|lease|materializ|kos-git|kos-step/, source)
    assert_operator source.lines.length, :<=, 30
  end

  private

  def managed_names(relative)
    paths = Rails.root.join(relative).children.reject { |path| path.basename.to_s.start_with?(".") }
    paths = paths.select { |path| path.join("SKILL.md").file? } if relative == "skills"
    paths
      .map { |path| path.basename.to_s }.sort
  end

  def frontmatter(path)
    YAML.safe_load(File.read(path).match(/\A---\n(.*?)\n---/m)[1])
  end
end
