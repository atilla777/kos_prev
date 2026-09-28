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
    refute metadata.key?("model")
    assert_includes source, "Load the `kos` skill"
    assert_equal 1, source.scan("$ARGUMENTS").length
    assert_includes source, "<kos-goal>"
    refute_match(/development mode|resume|session-id|kos-step/, source)
  end

  test "orchestrator coordinates but never performs substantive work" do
    source = normalized(Rails.root.join("skills/kos/SKILL.md"))

    assert_match(/`status --remote REMOTE`.*discover unfinished plans and tasks before creating replacement work/i, source)
    assert_match(/before project discovery .* run `installation check`/i, source)
    assert_match(/project is not registered, stop/i, source)
    assert_match(/dispatch independent claims in parallel/i, source)
    assert_equal %w[claim_id step task_id version], envelope_fields(source)
    assert_match(/never performs a workflow step/i, source)
    assert_match(/trust KOS state rather than worker prose/i, source)
    assert_match(/take over an active task only after deciding its worker has stopped/i, source)
    assert_match(/release only when the active task still matches the cancelled dispatch.*`task_id`.*`claim_id`.*`version`.*`step`/i,
      source)
    assert_match(/use takeover when immediate replacement is intended/i, source)
    assert_match(/abandon .* only with explicit user intent and the observed plan version/i, source)
    refute_match(/git status|git push|retry|\blease\b|review algorithm/i, source)
  end

  test "orchestrator preserves planning and workflow intent" do
    source = normalized(Rails.root.join("skills/kos/SKILL.md"))

    assert_match(/before creating or revising an unstarted plan, discover workflow keys/i, source)
    assert_match(/`development` workflow for ordinary implementation.*`fix` for defect correction.*`brief` for specification work/i,
      source)
    assert_match(/exact discovered custom key when the user requests one/i, source)
    assert_match(/requested workflow is absent, ask one material question and make no coordination mutation/i, source)
    assert_match(/never guess a key, create a fallback workflow, or silently substitute/i, source)
    assert_match(/sole supported orchestration command is `\/kos`/i, source)
    assert_match(/planning only, stop after storage, with every task pending and unclaimed/i, source)
    assert_match(/do not query ready tasks, claim, take over, or release work, or dispatch a worker after that planning-only write/i,
      source)
    assert_match(/goal explicitly authorizes execution, coordinate the plan's execution/i, source)
    assert_match(/intent is ambiguous, ask one material question before any ready-task query, claim, takeover, release, or worker dispatch/i,
      source)
  end

  test "orchestrator observes state after worker cancellation" do
    source = normalized(Rails.root.join("skills/kos/SKILL.md"))

    assert_match(/cancelling an OpenCode worker does not mutate KOS, clear its claim, change its version, or undo external effects/i,
      source)
    assert_match(/reread authoritative task state after known cancellation and before any takeover or later claim-release decision/i,
      source)
    assert_match(/after assessing possible external effects, release only when the active task still matches/i, source)
    assert_match(/never release unknown work based on age, inactivity, or inferred worker health/i, source)
  end

  test "worker executes exactly one immutable fenced step" do
    skill = normalized(Rails.root.join("skills/kos-worker/SKILL.md"))
    agent_path = Rails.root.join(".opencode/agents/kos-worker.md")
    agent = normalized(agent_path)
    metadata = frontmatter(agent_path)

    assert_equal "subagent", metadata.fetch("mode")
    assert_equal %w[description mode reasoningEffort], metadata.keys.sort
    assert_match(/immutable JSON envelope/i, agent)
    assert_equal %w[claim_id step task_id version], envelope_fields(agent)
    assert_match(/run `installation check` before reading task context or doing repository work/i, skill)
    assert_match(/require all four envelope values to match the active claim before doing work/i, skill)
    assert_match(/report exactly one allowed outcome .* using the original envelope/i, skill)
    assert_match(/never adopt a later claim, version, or step/i, skill)
    assert_match(/never execute the next step/i, skill)
    refute_match(/git (?:status|diff|push|commit)|retry|lock|lease/i, skill)
  end

  test "CLI skill is concise and names the complete public surface" do
    source = normalized(Rails.root.join("skills/kos-cli/SKILL.md"))

    %w[KOS_CLI_PATH KOS_API_URL KOS_API_TOKEN KOS_OPENCODE_MANIFEST health claim-id].each do |value|
      assert_includes source, value
    end
    assert_includes source, "installation check"
    [ "project create/show/resolve/update", "workflow create/list/show/schema", "plan put/list/show/abandon",
      "task list/ready/show/context/result/claim/takeover/release/report/answer" ].each do |surface|
      assert_includes source, surface
    end
    [ "project show --repository-identity IDENTITY", "project resolve --remote REMOTE", "status --remote REMOTE",
      "workflow list [--key KEY]", "workflow show ID",
      "workflow schema", "plan show --project-id ID --key KEY", "task context ID" ].each do |signature|
      assert_includes source, signature
    end
    (0..3).each { |status| assert_includes source, "`#{status}`" }
    refute_match(/session-id|task-type|resume|\blease\b|materializ|kos-git|kos-step|Net::HTTP|ActiveRecord/, source)
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

  def normalized(path)
    File.read(path).gsub(/\s+/, " ")
  end

  def envelope_fields(source)
    source.scan(/`(task_id|claim_id|version|step)`/).flatten.uniq.sort
  end
end
