require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  test "validates the minimal workflow shape and generic transitions" do
    workflow = create_workflow

    assert_equal %w[work review], workflow.step_ids
    assert_equal({ "next_step" => "review" }, workflow.action_for("work", "done"))

    invalid = valid_workflow_definition.deep_dup
    invalid["steps"][0]["extra"] = true
    assert_not Workflow.new(key: "invalid", name: "Invalid", revision: 1, definition_json: invalid).valid?
  end

  test "rejects unknown targets and reachable workflows without completion" do
    unknown = valid_workflow_definition.deep_dup
    unknown["steps"][0]["outcomes"]["done"] = { "next_step" => "missing" }
    assert_not Workflow.new(key: "unknown", name: "Unknown", revision: 1, definition_json: unknown).valid?

    closed = valid_workflow_definition.deep_dup
    closed["steps"][1]["outcomes"] = { "again" => { "next_step" => "work" } }
    assert_not Workflow.new(key: "closed", name: "Closed", revision: 1, definition_json: closed).valid?
  end

  test "workflow revisions are unique and immutable" do
    workflow = create_workflow(key: "delivery", revision: 1)
    assert create_workflow(key: "delivery", revision: 2)
    assert_raises(ActiveRecord::RecordInvalid) { create_workflow(key: "delivery", revision: 1) }

    changed = workflow.definition_json.deep_dup
    changed["steps"][0]["instruction"] = "Changed"
    assert_not workflow.update(definition_json: changed)
    assert_not workflow.update(key: "renamed")
    assert_not workflow.update(name: "Renamed")
    assert_not workflow.update(revision: 3)
  end


  test "bounds workflow steps outcomes and text by bytes" do
    steps = CoordinationLimits::MAX_STEPS_PER_WORKFLOW.times.map do |index|
      action = index == CoordinationLimits::MAX_STEPS_PER_WORKFLOW - 1 ?
        { "complete_task" => true } : { "next_step" => "step-#{index + 1}" }
      { "id" => "step-#{index}", "name" => "Step", "instruction" => "Work", "outcomes" => { "done" => action } }
    end
    assert Workflow.new(key: "bounded", name: "Bounded", revision: 1,
      definition_json: { "steps" => steps }).valid?

    too_many_steps = steps + [ steps.last.merge("id" => "extra") ]
    assert_not Workflow.new(key: "large", name: "Large", revision: 1,
      definition_json: { "steps" => too_many_steps }).valid?

    outcomes = CoordinationLimits::MAX_OUTCOMES_PER_WORKFLOW.times.to_h do |index|
      [ "outcome-#{index}", { "complete_task" => true } ]
    end
    definition = { "steps" => [ {
      "id" => "work", "name" => "Work", "instruction" => "x" * CoordinationLimits::MAX_TEXT_BYTES,
      "outcomes" => outcomes
    } ] }
    assert Workflow.new(key: "outcomes", name: "Outcomes", revision: 1, definition_json: definition).valid?
    definition["steps"][0]["outcomes"]["extra"] = { "complete_task" => true }
    assert_not Workflow.new(key: "too-many", name: "Too many", revision: 1, definition_json: definition).valid?

    definition = valid_workflow_definition.deep_dup
    definition["steps"][0]["id"] = "é" * 51
    assert_not Workflow.new(key: "bytes", name: "Bytes", revision: 1, definition_json: definition).valid?
    assert_not Workflow.new(key: "name-bytes", name: "é" * 101, revision: 1,
      definition_json: valid_workflow_definition).valid?
  end
end
