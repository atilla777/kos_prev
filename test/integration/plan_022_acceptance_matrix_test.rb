require "test_helper"

class Plan022AcceptanceMatrixTest < ActiveSupport::TestCase
  Criterion = Data.define(:text, :tests)

  COVERAGE = [
    Criterion.new("agent only ID/context", [
      [ "test/skills/kos_skills_test.rb", "step executor derives context and atomically reports Markdown itself" ]
    ]),
    Criterion.new("context index no bodies", [
      [ "test/integration/tasks_api_test.rb", "context returns the bounded agent projection and artifact bodies are read separately" ]
    ]),
    Criterion.new("separate artifact", [
      [ "test/integration/tasks_api_test.rb", "context returns the bounded agent projection and artifact bodies are read separately" ]
    ]),
    Criterion.new("atomic artifact+transition", [
      [ "test/models/task_lifecycle_test.rb", "accepted artifacts transition atomically and a repeated successful step replaces its record" ]
    ]),
    Criterion.new("crash before completion unchanged", [
      [ "test/models/brief_task_graph_test.rb", "rolls back every child when persistence fails partway through materialization" ],
      [ "test/models/task_lifecycle_test.rb", "validates artifact bytes before changing task state" ]
    ]),
    Criterion.new("lost response ordinary show", [
      [ "test/integration/acceptance_scenarios_test.rb", "a dropped report response is recovered by show without a duplicate transition" ]
    ]),
    Criterion.new("stale/wrong no write", [
      [ "test/integration/tasks_api_test.rb", "stale owner claim and wrong step reports atomically leave state and artifacts unchanged" ]
    ]),
    Criterion.new("bad predecessor backward allowed", [
      [ "test/integration/acceptance_scenarios_test.rb", "built in correction outcomes route backward and verification failures do not complete" ]
    ]),
    Criterion.new("repeated replaces", [
      [ "test/models/task_lifecycle_test.rb", "accepted artifacts transition atomically and a repeated successful step replaces its record" ]
    ]),
    Criterion.new("answer stored/restart", [
      [ "test/integration/acceptance_scenarios_test.rb", "a paused question and answer survive repeated interruption in server state" ]
    ]),
    Criterion.new("scheduler only ID", [
      [ "test/skills/kos_skills_test.rb", "scheduler dispatches built-ins by exact step with an ID-only prompt" ]
    ]),
    Criterion.new("scheduler no Markdown/Git", [
      [ "test/skills/kos_skills_test.rb", "scheduler has no step artifact Git or result-parsing policy" ]
    ]),
    Criterion.new("profile policy", [
      [ "test/skills/kos_skills_test.rb", "profiles enforce exact authority and publish alone can commit or push" ],
      [ "test/skills/kos_skills_test.rb", "review verify plan and diagnose profiles are read-only" ]
    ]),
    Criterion.new("independent read-only review", [
      [ "test/integration/acceptance_scenarios_test.rb", "a moved base repeats checks and review before one publication commit" ]
    ]),
    Criterion.new("publish->verify", [
      [ "test/integration/acceptance_scenarios_test.rb", "built in development and fix lifecycles atomically progress through verification" ]
    ]),
    Criterion.new("verify remote independently", [
      [ "test/skills/kos_skills_test.rb", "verification independently observes remote publication" ]
    ]),
    Criterion.new("verify failure not complete", [
      [ "test/integration/acceptance_scenarios_test.rb", "built in correction outcomes route backward and verification failures do not complete" ]
    ]),
    Criterion.new("nonpublish no commit/push", [
      [ "test/skills/kos_skills_test.rb", "profiles enforce exact authority and publish alone can commit or push" ]
    ]),
    Criterion.new("existing IDs/relationships/workflows/worktrees", [
      [ "test/integration/repository_identity_migration_test.rb", "backfill and reversal preserve IDs relationships workflow snapshots and execution state" ],
      [ "test/integration/acceptance_scenarios_test.rb", "two tasks retain independent ownership artifacts and uncommitted worktrees" ]
    ]),
    Criterion.new("clean install assets/workflows", [
      [ "test/integration/gem_package_test.rb", "installs the complete OpenCode integration from the checkout" ],
      [ "test/integration/built_in_catalog_seed_test.rb", "a fresh prepared database receives the idempotent built-in catalog" ]
    ]),
    Criterion.new("real development/fix/brief scenarios E2E", [
      [ "test/integration/acceptance_scenarios_test.rb", "built in development and fix lifecycles atomically progress through verification" ],
      [ "test/integration/acceptance_scenarios_test.rb", "brief materializes its exact validated graph at publish before verification completes it" ]
    ]),
    Criterion.new("no local tasks/id dir", [
      [ "test/integration/acceptance_scenarios_test.rb", "task state and accepted artifact survive restart without a local task artifact directory" ]
    ]),
    Criterion.new("bin/check", [])
  ].freeze

  EXPECTED_CRITERIA = [
    "agent only ID/context", "context index no bodies", "separate artifact", "atomic artifact+transition",
    "crash before completion unchanged", "lost response ordinary show", "stale/wrong no write",
    "bad predecessor backward allowed", "repeated replaces", "answer stored/restart", "scheduler only ID",
    "scheduler no Markdown/Git", "profile policy", "independent read-only review", "publish->verify",
    "verify remote independently", "verify failure not complete", "nonpublish no commit/push",
    "existing IDs/relationships/workflows/worktrees", "clean install assets/workflows",
    "real development/fix/brief scenarios E2E", "no local tasks/id dir", "bin/check"
  ].freeze

  test "the exact 23 acceptance criteria map in order to executable tests or the check contract" do
    assert_equal EXPECTED_CRITERIA, COVERAGE.map(&:text)

    inventory = executable_test_inventory
    COVERAGE.each_with_index do |criterion, index|
      next if criterion.text == "bin/check"

      assert_predicate criterion.tests, :any?, "criterion #{index + 1} has no executable coverage"
      criterion.tests.each do |relative_path, test_name|
        assert_includes inventory.fetch(relative_path), test_name,
          "criterion #{index + 1} maps to a missing executable test"
      end
    end
  end

  test "clean install and workflow coverage use the exact managed inventory and catalog" do
    assert_equal %w[kos-brief.md kos-fix.md kos.md], managed_names(".opencode/commands")
    assert_equal %w[
      kos-brief.md kos-diagnose.md kos-document.md kos-implement.md kos-plan.md kos-publish.md kos-review.md
      kos-step-advanced.md kos-step-standard.md kos-verify.md
    ], managed_names(".opencode/agents")
    assert_equal %w[kos kos-brief kos-cli kos-create kos-git kos-step okf], managed_names("skills")
    assert_equal %w[brief development fix], BuiltInCatalog.definitions.keys.sort
    assert_equal %w[brief review publish verify], catalog_steps("brief")
    assert_equal %w[plan implement document review publish verify], catalog_steps("development")
    assert_equal %w[diagnose plan implement document review publish verify], catalog_steps("fix")
  end

  test "deterministic scenarios do not claim live model release evidence" do
    testing_contract = Rails.root.join("docs/testing.md").read
    assert_includes testing_contract, "Live model execution remains separate release evidence"
    assert_includes testing_contract, "does not claim\nthat evidence has already been produced"

    check = Rails.root.join("bin/check")
    assert_predicate check, :executable?
    assert_equal [ "bin/lint", "RAILS_ENV=test bin/rails db:prepare", "bin/test" ],
      check.readlines(chomp: true).reject { |line| line.empty? || line.start_with?("#!", "set ") }
  end

  private

  def executable_test_inventory
    Rails.root.glob("test/**/*_test.rb").to_h do |path|
      [ path.relative_path_from(Rails.root).to_s, test_names(RubyVM::AbstractSyntaxTree.parse_file(path.to_s)) ]
    end
  end

  def test_names(node, names = [])
    return names unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)

    if node.type == :FCALL && node.children.first == :test
      argument = node.children[1]&.children&.first
      names << argument.children.first if argument&.type == :STR
    end
    node.children.each { |child| test_names(child, names) }
    names
  end

  def managed_names(relative_path)
    Rails.root.join(relative_path).children.map { |path| path.basename.to_s }.sort
  end

  def catalog_steps(key)
    BuiltInCatalog.definitions.fetch(key).fetch("steps").pluck("id")
  end
end
