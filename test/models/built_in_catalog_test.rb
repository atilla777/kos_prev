require "test_helper"

class BuiltInCatalogTest < ActiveSupport::TestCase
  test "installs concise generic immutable revisions idempotently" do
    assert_difference -> { Workflow.count }, 3 do
      BuiltInCatalog.install!
    end
    assert_no_difference -> { Workflow.count } do
      BuiltInCatalog.install!
    end

    assert BuiltInCatalog.installed?
    assert_equal %w[brief development fix], Workflow.where(revision: BuiltInCatalog::REVISION).order(:key).pluck(:key)
    Workflow.where(revision: BuiltInCatalog::REVISION).find_each do |workflow|
      workflow.definition_json.fetch("steps").each do |step|
        assert_equal %w[id instruction name outcomes], step.keys.sort
        assert_equal({ "pause" => "needs_human" }, step.dig("outcomes", "needs_human"))
        assert_equal({ "pause" => "blocked" }, step.dig("outcomes", "blocked"))
      end
      assert workflow.valid?
    end
  end

  test "installs a changed catalog as new revisions while existing tasks remain pinned" do
    legacy_definition = BuiltInCatalog.definitions.fetch("brief").deep_dup
    legacy_definition.fetch("steps").first["instruction"] = "Legacy planning instruction."
    legacy = create_workflow(key: "brief", revision: BuiltInCatalog::REVISION - 1,
      definition: legacy_definition, name: "Brief")
    task = create_task(workflow: legacy)

    assert_difference -> { Workflow.count }, 3 do
      BuiltInCatalog.install!
    end
    assert_no_difference -> { Workflow.count } do
      BuiltInCatalog.install!
    end

    assert_equal legacy.id, task.reload.workflow_id
    assert_equal legacy_definition, legacy.reload.definition_json
    assert_equal BuiltInCatalog.definitions.fetch("brief"),
      Workflow.find_by!(key: "brief", revision: BuiltInCatalog::REVISION).definition_json
  end

  test "worker instructions do not assign orchestrator coordination" do
    instructions = BuiltInCatalog.definitions.values.flat_map do |definition|
      definition.fetch("steps").pluck("instruction")
    end

    instructions.each do |instruction|
      refute_match(/\b(?:creat|replac|claim|answer|schedul)\w*\b|\btake\s+over\b|\btakeover\b/i, instruction)
    end
    brief_instructions = BuiltInCatalog.definitions.fetch("brief").fetch("steps").pluck("instruction")
    assert_equal [
      "Specify the requested behavior and its acceptance criteria.",
      "Review the complete specification independently and report actionable findings.",
      "Publish the approved specification and observe the result."
    ], brief_instructions
    brief_instructions.each { |instruction| refute_match(/task plan|implement/i, instruction) }
    assert_equal "Publish the approved specification and observe the result.",
      BuiltInCatalog.definitions.fetch("brief").fetch("steps").find { |step| step.fetch("id") == "publish" }
        .fetch("instruction")
  end

  test "installation rejects a conflicting current revision atomically" do
    create_workflow(key: "fix", revision: BuiltInCatalog::REVISION, name: "Conflicting fix")

    assert_raises(ActiveRecord::RecordInvalid) { BuiltInCatalog.install! }
    refute BuiltInCatalog.installed?
    assert_equal [ "fix" ], Workflow.where(revision: BuiltInCatalog::REVISION).pluck(:key)
  end
end
