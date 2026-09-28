require "test_helper"

class DomainSchemaTest < ActiveSupport::TestCase
  test "contains exactly the five named domain tables" do
    internal = %w[ar_internal_metadata schema_migrations]
    expected = %w[projects workflows task_plans tasks task_dependencies]
    assert_equal expected.sort, (ActiveRecord::Base.connection.tables - internal).sort
  end

  test "defines the minimal task state and database constraints" do
    assert_equal %w[accepted_results answer claim_id created_at current_step description_markdown id key pause_kind
      pause_message pause_step status task_plan_id title updated_at version workflow_id], Task.column_names.sort
    assert_equal "pending", Task.columns_hash.fetch("status").default
    assert_equal 0, Task.columns_hash.fetch("version").default
    assert_equal({}, Task.column_defaults.fetch("accepted_results"))

    task = create_task
    assert_raises(ActiveRecord::StatementInvalid) { task.update_columns(status: "cancelled") }
    assert_raises(ActiveRecord::StatementInvalid) { task.update_columns(version: -1) }
  end

  test "enforces plan-local task keys and workflow revisions" do
    workflow = create_workflow(key: "delivery", revision: 1)
    plan = create_task_plan
    create_task(task_plan: plan, workflow:, key: "one")
    assert_raises(ActiveRecord::RecordNotUnique) do
      Task.insert_all!([ {
        task_plan_id: plan.id, workflow_id: workflow.id, key: "one", title: "Duplicate",
        description_markdown: "Duplicate", status: "pending", current_step: "work", version: 0,
        accepted_results: {}, created_at: Time.current, updated_at: Time.current
      } ])
    end
    assert create_workflow(key: "delivery", revision: 2)
  end
end
