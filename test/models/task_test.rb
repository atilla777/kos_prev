require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "accepts any step from its workflow" do
    assert create_task(current_step: "check").persisted?
  end

  test "rejects a current step outside its workflow" do
    task = create_task

    assert_not task.update(current_step: "publish")
    assert_includes task.errors[:current_step], "must identify a step in the task workflow"
  end

  test "accepts a parent from the same project" do
    project = create_project
    parent = create_task(project:)

    assert create_task(project:, parent:).persisted?
  end

  test "rejects a parent from another project" do
    task = create_task
    other_parent = create_task

    assert_not task.update(parent: other_parent)
    assert_includes task.errors[:parent], "must belong to the same project"
  end

  test "rejects a task as its own parent" do
    task = create_task

    assert_not task.update(parent: task)
    assert_includes task.errors[:parent], "cannot create a cycle"
  end

  test "rejects direct and indirect parent cycles" do
    project = create_project
    first = create_task(project:)
    second = create_task(project:, parent: first)
    third = create_task(project:, parent: second)

    assert_not first.update(parent: second)
    assert_not first.update(parent: third)
  end

  test "accepts a deep acyclic parent hierarchy" do
    project = create_project
    root = create_task(project:)
    child = create_task(project:, parent: root)

    assert create_task(project:, parent: child).persisted?
  end

  test "does not allow a task to move between projects" do
    task = create_task

    assert_not task.update(project: create_project(name: "Other"))
    assert_includes task.errors[:project], "cannot change after task creation"
  end

  test "does not allow a task to change workflow" do
    task = create_task

    assert_not task.update(workflow: create_workflow(name: "Other"))
    assert_includes task.errors[:workflow], "cannot change after task creation"
  end

  test "does not allow tasks to be destroyed" do
    task = create_task

    assert_not task.destroy
    assert task.persisted?
    assert_includes task.errors[:base], "tasks cannot be deleted; cancel the task instead"
  end

  test "allows description edits only before the first claim" do
    task = create_task
    assert task.update(description_markdown: "Before claim")

    TaskLifecycle.new.claim_next!(project: task.project, owner_id: "session")

    assert_not task.update(description_markdown: "After claim")
    assert_includes task.errors[:description_markdown], "can change only while the task is pending and unclaimed"

    cancelled = create_task
    TaskLifecycle.new.cancel!(task_id: cancelled.id)
    assert_not cancelled.reload.update(description_markdown: "After cancellation")
  end

  test "keeps title and task type immutable" do
    task = create_task

    assert_not task.update(title: "Renamed")
    assert_not task.update(task_type: create_task_type(name: "Other", workflow: task.workflow))
  end

  test "keeps a creation key immutable" do
    task = create_task
    task.update_columns(creation_key: "request:fix:sha256:abc")

    assert_not task.reload.update(creation_key: "request:fix:sha256:def")
    assert_includes task.errors[:creation_key], "cannot change after task creation"
  end

  test "allows parent edits only while pending and unclaimed" do
    project = create_project
    first_parent = create_task(project:)
    second_parent = create_task(project:)
    task = create_task(project:, parent: first_parent)
    assert task.update(parent: second_parent)

    TaskLifecycle.new.cancel!(task_id: first_parent.id)
    TaskLifecycle.new.cancel!(task_id: second_parent.id)
    TaskLifecycle.new.claim_next!(project:, owner_id: "session")

    assert_not task.update(parent: nil)
    assert_includes task.errors[:parent], "can change only while the task is pending and unclaimed"
  end

  test "lifecycle state changes only through TaskLifecycle" do
    task = create_task

    assert_not task.update(status: "completed", current_step: "check", owner_id: "owner", claim_version: 1,
      lease_expires_at: 1.hour.from_now, accepted_artifacts: { "develop" => {} }, pause_message: "Question",
      pause_step: "develop", pause_claim_version: 1, human_answer: "Answer", human_answer_step: "develop",
      human_answer_claim_version: 1)
    assert_includes task.errors[:base], "lifecycle state can change only through TaskLifecycle"
  end
end
