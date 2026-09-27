require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  test "accepts a complete workflow including a backward transition" do
    workflow = Workflow.new(name: "Workflow", definition_json: valid_workflow_definition)

    assert workflow.valid?
    assert_equal %w[develop check], workflow.step_ids
  end

  test "requires a closed root with a non-empty steps array" do
    [ [], {}, { "steps" => [] }, { "steps" => [], "extra" => true } ].each do |definition|
      assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?
    end
  end

  test "requires every step field with the expected type" do
    definition = valid_workflow_definition
    definition["steps"][0].delete("instruction")
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?

    definition = valid_workflow_definition
    definition["steps"][0]["artifact_template"] = []
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?

    definition = valid_workflow_definition
    definition["steps"][0]["extra"] = true
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?
  end

  test "requires an explicit standard or advanced model tier for new workflows" do
    definition = valid_workflow_definition
    definition["steps"][0].delete("model_tier")
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?

    [ "", "fast", nil, [] ].each do |tier|
      definition = valid_workflow_definition
      definition["steps"][0]["model_tier"] = tier
      assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?
    end
  end

  test "requires an explicit main or subagent execution mode for new workflows" do
    definition = valid_workflow_definition
    definition["steps"][0].delete("execution_mode")
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?

    [ "", "worker", nil, [] ].each do |mode|
      definition = valid_workflow_definition
      definition["steps"][0]["execution_mode"] = mode
      assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?
    end

    assert_equal %w[main subagent], valid_workflow_definition.fetch("steps").pluck("execution_mode")
  end

  test "uses advanced as the effective tier for an unchanged persisted legacy workflow" do
    definition = valid_workflow_definition.deep_dup
    definition["steps"].each { |step| step.delete("model_tier"); step.delete("execution_mode") }
    workflow = Workflow.new(name: "Legacy", definition_json: definition)
    workflow.save!(validate: false)
    workflow.reload

    assert workflow.valid?
    assert_equal "advanced", workflow.step_for("develop").fetch("model_tier")
    assert_equal "subagent", workflow.step_for("develop").fetch("execution_mode")
    assert workflow.definition_for_execution.fetch("steps").all? { |step| step["model_tier"] == "advanced" }
    task_type = create_task_type(name: "Legacy", workflow:)
    task = create_task(workflow:, task_type:)
    assert_equal workflow, task.workflow
  end

  test "uses subagent as the effective mode for the previous persisted workflow shape" do
    definition = valid_workflow_definition.deep_dup
    definition["steps"].each { |step| step.delete("execution_mode") }
    workflow = Workflow.new(name: "Previous", definition_json: definition)
    workflow.save!(validate: false)

    assert workflow.reload.valid?
    assert workflow.definition_for_execution.fetch("steps").all? { |step| step["execution_mode"] == "subagent" }
  end

  test "former built-in step ids accept only their declared generic execution fields" do
    ids = %w[diagnose plan implement document brief review publish]
    steps = ids.each_with_index.map do |id, index|
      action = index == ids.length - 1 ? { "complete_task" => true } : { "next_step" => ids.fetch(index + 1) }
      {
        "id" => id,
        "name" => id.titleize,
        "execution_mode" => index.even? ? "main" : "subagent",
        "model_tier" => index.even? ? "standard" : "advanced",
        "instruction" => "Execute custom #{id} behavior.",
        "artifact_template" => "# #{id.titleize}",
        "outcomes" => { "done" => action }
      }
    end

    workflow = Workflow.create!(name: "Name collisions", definition_json: { "steps" => steps })

    assert_equal steps, workflow.definition_for_execution.fetch("steps")
  end

  test "requires non-empty unique step ids and names" do
    definition = valid_workflow_definition
    definition["steps"][0]["id"] = ""
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?

    definition = valid_workflow_definition
    definition["steps"][1]["id"] = "develop"
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?

    definition = valid_workflow_definition
    definition["steps"][0]["name"] = ""
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?
  end

  test "requires non-empty outcomes with non-empty names" do
    definition = valid_workflow_definition
    definition["steps"][0]["outcomes"] = {}
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?

    definition = valid_workflow_definition
    definition["steps"][0]["outcomes"][""] = { "next_step" => "check" }
    assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?
  end

  test "requires exactly one known action per outcome" do
    invalid_actions = [
      {},
      { "next_step" => "check", "pause" => "blocked" },
      { "unknown" => true }
    ]

    invalid_actions.each do |action|
      definition = valid_workflow_definition
      definition["steps"][0]["outcomes"]["ready"] = action
      assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?
    end
  end

  test "validates each action value" do
    invalid_actions = [
      { "next_step" => "missing" },
      { "pause" => "later" },
      { "complete_task" => false }
    ]

    invalid_actions.each do |action|
      definition = valid_workflow_definition
      definition["steps"][0]["outcomes"]["ready"] = action
      assert_not Workflow.new(name: "Workflow", definition_json: definition).valid?
    end
  end

  test "requires every reachable step to have a path to completion" do
    definition = valid_workflow_definition.deep_dup
    definition["steps"][1]["outcomes"] = { "again" => { "next_step" => "develop" } }
    workflow = Workflow.new(name: "Closed cycle", definition_json: definition)

    assert_not workflow.valid?
    assert_includes workflow.errors[:definition_json],
      "reachable steps without a path to complete_task: develop, check"

    definition = valid_workflow_definition.deep_dup
    definition["steps"] << {
      "id" => "dead", "name" => "Dead", "execution_mode" => "main", "model_tier" => "standard",
      "instruction" => "Wait.", "artifact_template" => "# Dead",
      "outcomes" => { "wait" => { "pause" => "blocked" } }
    }
    definition["steps"][0]["outcomes"]["dead"] = { "next_step" => "dead" }
    workflow = Workflow.new(name: "Dead branch", definition_json: definition)

    assert_not workflow.valid?
    assert_includes workflow.errors[:definition_json], "reachable steps without a path to complete_task: dead"
  end

  test "allows reachable cycles with a completion exit and ignores unreachable dead steps" do
    definition = valid_workflow_definition.deep_dup
    definition["steps"] << {
      "id" => "unused", "name" => "Unused", "execution_mode" => "subagent", "model_tier" => "advanced",
      "instruction" => "Wait.", "artifact_template" => "# Unused",
      "outcomes" => { "again" => { "next_step" => "unused" } }
    }

    assert Workflow.new(name: "Completable", definition_json: definition).valid?
  end

  test "prevents new tasks from using a persisted legacy workflow that cannot complete" do
    definition = valid_workflow_definition.deep_dup
    definition["steps"][1]["outcomes"] = { "again" => { "next_step" => "develop" } }
    workflow = Workflow.new(name: "Legacy closed cycle", definition_json: definition)
    workflow.save!(validate: false)
    task_type = create_task_type(workflow:)

    assert_no_difference -> { Task.count } do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        TaskLifecycle.new.create!(project: create_project, task_type:, title: "Unsupported",
          description_markdown: "Cannot complete")
      end
      assert_includes error.record.errors[:workflow], "must have a valid executable definition"
    end
  end

  test "allows definition changes before a task uses the workflow" do
    workflow = create_workflow
    create_task_type(workflow:)

    definition = valid_workflow_definition
    definition["steps"][0]["name"] = "Implementation"

    assert workflow.update(definition_json: definition)
  end

  test "rejects definition changes after a task uses the workflow" do
    task = create_task
    workflow = task.workflow
    original_definition = workflow.definition_json.deep_dup
    changed_definition = original_definition.deep_dup
    changed_definition["steps"][0]["name"] = "Implementation"

    assert_not workflow.update(definition_json: changed_definition)
    assert_includes workflow.errors[:definition_json], "cannot change after the workflow is used by a task"
    assert_equal original_definition, workflow.reload.definition_json
  end

  test "detects an in-place definition change after use" do
    workflow = create_task.workflow
    workflow.definition_json["steps"][0]["name"] = "Implementation"

    assert_not workflow.save
    assert_equal "Develop", workflow.reload.definition_json["steps"][0]["name"]
  end

  test "allows the name of a used workflow to change" do
    workflow = create_task.workflow

    assert workflow.update(name: "Renamed")
  end

  test "remains immutable because tasks cannot change workflow or be destroyed" do
    task = create_task
    workflow = task.workflow

    assert_not task.update(workflow: create_workflow(name: "Other"))
    assert_not task.destroy

    changed_definition = workflow.definition_json.deep_dup
    changed_definition["steps"][0]["name"] = "Implementation"
    assert_not workflow.update(definition_json: changed_definition)
  end
end
