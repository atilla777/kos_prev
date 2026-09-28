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
end
