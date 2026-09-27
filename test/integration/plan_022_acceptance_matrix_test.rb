require "test_helper"

class Plan022AcceptanceMatrixTest < ActiveSupport::TestCase
  Criterion = Data.define(:text, :layer, :tests)

  COVERAGE = [
    Criterion.new("agent only ID/context", :installed_asset, [
      [ "test/skills/kos_skills_test.rb", "step guidance uses workflow context as the complete role contract" ]
    ]),
    Criterion.new("context index no bodies", :domain_lifecycle, [
      [ "test/integration/tasks_api_test.rb", "context returns the bounded agent projection and artifact bodies are read separately" ]
    ]),
    Criterion.new("separate artifact", :domain_lifecycle, [
      [ "test/integration/tasks_api_test.rb", "context returns the bounded agent projection and artifact bodies are read separately" ]
    ]),
    Criterion.new("atomic artifact+transition", :domain_lifecycle, [
      [ "test/models/task_lifecycle_test.rb", "accepted artifacts transition atomically and a repeated successful step replaces its record" ]
    ]),
    Criterion.new("crash before completion unchanged", :scheduler_integration, [
      [ "test/skills/kos_scheduler_recovery_test.rb", "a child crash stops after one unchanged dispatch" ]
    ]),
    Criterion.new("lost response ordinary show", :domain_lifecycle, [
      [ "test/integration/acceptance_scenarios_test.rb", "a dropped report response is recovered by show without a duplicate transition" ]
    ]),
    Criterion.new("stale/wrong no write", :domain_lifecycle, [
      [ "test/integration/tasks_api_test.rb", "stale owner claim and wrong step reports atomically leave state and artifacts unchanged" ]
    ]),
    Criterion.new("bad predecessor backward allowed", :domain_lifecycle, [
      [ "test/integration/acceptance_scenarios_test.rb", "built in correction outcomes route backward without completing" ]
    ]),
    Criterion.new("repeated replaces", :domain_lifecycle, [
      [ "test/models/task_lifecycle_test.rb", "accepted artifacts transition atomically and a repeated successful step replaces its record" ]
    ]),
    Criterion.new("answer stored/restart", :domain_lifecycle, [
      [ "test/integration/acceptance_scenarios_test.rb", "a paused question and answer survive repeated interruption in server state" ]
    ]),
    Criterion.new("scheduler only ID", :scheduler_integration, [
      [ "test/integration/installed_scheduler_execution_test.rb", "installed built-in commands schedule complete workflows by mode and tier" ]
    ]),
    Criterion.new("scheduler no Markdown/Git", :scheduler_integration, [
      [ "test/integration/installed_scheduler_execution_test.rb", "installed built-in commands schedule complete workflows by mode and tier" ]
    ]),
    Criterion.new("profile policy", :installed_asset, [
      [ "test/skills/kos_skills_test.rb", "installs exactly two generic tier profiles without role policy" ],
      [ "test/skills/kos_skills_test.rb", "built-in workflow instructions retain delivery and independent review boundaries" ]
    ]),
    Criterion.new("independent read-only review", :git_fixture, [
      [ "test/integration/acceptance_scenarios_test.rb", "a moved base repeats content checks and exact-range review before publication" ]
    ]),
    Criterion.new("publish completes", :domain_lifecycle, [
      [ "test/integration/acceptance_scenarios_test.rb", "built in development and fix lifecycles complete at publication" ]
    ]),
    Criterion.new("publish observes remote", :git_fixture, [
      [ "test/integration/acceptance_scenarios_test.rb", "publication recovery pushes or reuses the exact range before and after an ambiguous result" ]
    ]),
    Criterion.new("publication prerequisites gate completion", :domain_lifecycle, [
      [ "test/models/brief_task_graph_test.rb", "rejects published before materialization without accepting an artifact" ]
    ]),
    Criterion.new("no push before publish", :git_fixture, [
      [ "test/integration/acceptance_scenarios_test.rb", "two tasks retain independent ownership artifacts and local commit ranges" ]
    ]),
    Criterion.new("existing IDs/relationships/workflows/worktrees", :migration_and_git, [
      [ "test/integration/repository_identity_migration_test.rb", "backfill and reversal preserve IDs relationships workflow snapshots and execution state" ],
      [ "test/integration/acceptance_scenarios_test.rb", "two tasks retain independent ownership artifacts and local commit ranges" ]
    ]),
    Criterion.new("clean install assets/workflows", :package_smoke, [
      [ "test/integration/gem_package_test.rb", "installs the complete OpenCode integration from the checkout" ],
      [ "test/integration/built_in_catalog_seed_test.rb", "a fresh prepared database receives the idempotent built-in catalog" ]
    ]),
    Criterion.new("deterministic built-in scheduler scenarios", :scheduler_integration, [
      [ "test/integration/installed_scheduler_execution_test.rb", "installed built-in commands schedule complete workflows by mode and tier" ]
    ]),
    Criterion.new("no local tasks/id dir", :domain_lifecycle, [
      [ "test/integration/acceptance_scenarios_test.rb", "task state and accepted artifact survive restart without a local task artifact directory" ]
    ]),
    Criterion.new("bin/check", :repository_check, [])
  ].freeze

  EXPECTED_CRITERIA = [
    "agent only ID/context", "context index no bodies", "separate artifact", "atomic artifact+transition",
    "crash before completion unchanged", "lost response ordinary show", "stale/wrong no write",
    "bad predecessor backward allowed", "repeated replaces", "answer stored/restart", "scheduler only ID",
    "scheduler no Markdown/Git", "profile policy", "independent read-only review", "publish completes",
    "publish observes remote", "publication prerequisites gate completion", "no push before publish",
    "existing IDs/relationships/workflows/worktrees", "clean install assets/workflows",
    "deterministic built-in scheduler scenarios", "no local tasks/id dir", "bin/check"
  ].freeze

  test "the 23 acceptance criteria map in order to executable tests or the check contract" do
    assert_equal EXPECTED_CRITERIA, COVERAGE.map(&:text)
    assert_equal %i[
      domain_lifecycle git_fixture installed_asset migration_and_git package_smoke repository_check
      scheduler_integration
    ], COVERAGE.map(&:layer).uniq.sort

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
    assert_equal %w[kos-brief.md kos-fix.md kos-task.md kos.md], managed_names(".opencode/commands")
    assert_equal %w[kos-step-advanced.md kos-step-standard.md], managed_names(".opencode/agents")
    assert_equal %w[kos kos-cli kos-git kos-step okf], managed_names("skills")
    assert_equal %w[brief development fix], BuiltInCatalog.definitions.keys.sort
    assert_equal %w[brief review publish], catalog_steps("brief")
    assert_equal %w[plan implement review publish], catalog_steps("development")
    assert_equal %w[diagnose plan implement review publish], catalog_steps("fix")
  end

  test "deterministic scenarios do not claim live model release evidence" do
    testing_contract = Rails.root.join("docs/testing.md").read
    assert_includes testing_contract, "Live model execution remains separate release evidence"
    assert_includes testing_contract, "does not claim\nthat evidence has already been produced"

    check = Rails.root.join("bin/check")
    assert_predicate check, :executable?
    assert_equal [ "bin/lint", "RAILS_ENV=test bin/rails db:prepare", "RAILS_ENV=test bin/rails zeitwerk:check", "bin/test" ],
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
