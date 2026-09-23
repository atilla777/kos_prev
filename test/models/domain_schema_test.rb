require "test_helper"

class DomainSchemaTest < ActiveSupport::TestCase
  DOMAIN_TABLES = %w[projects workflows task_types tasks task_dependencies].freeze

  test "contains exactly the five domain tables" do
    internal_tables = %w[ar_internal_metadata schema_migrations]

    assert_equal DOMAIN_TABLES.sort, (ActiveRecord::Base.connection.tables - internal_tables).sort
  end

  test "defines required columns, optional ownership fields, and task defaults" do
    required_columns = {
      Project => %w[name remote_url repository_identity default_branch created_at updated_at],
      Workflow => %w[name definition_json created_at],
      TaskType => %w[key name workflow_id created_at updated_at],
      Task => %w[project_id task_type_id workflow_id title description_markdown status current_step
        claim_version accepted_artifacts created_at updated_at],
      TaskDependency => %w[task_id blocker_id]
    }

    required_columns.each do |model, column_names|
      column_names.each { |name| assert_equal false, model.columns_hash.fetch(name).null }
    end

    assert Task.columns_hash.fetch("parent_id").null
    assert Task.columns_hash.fetch("owner_id").null
    assert Task.columns_hash.fetch("creation_key").null
    assert Task.columns_hash.fetch("lease_expires_at").null
    assert_equal "pending", Task.columns_hash.fetch("status").default
    assert_equal 0, Task.columns_hash.fetch("claim_version").default
    assert_equal({}, Task.column_defaults.fetch("accepted_artifacts"))
  end

  test "enforces unique task type keys in the database" do
    workflow = create_workflow
    create_task_type(key: "feature", workflow:)

    assert_raises(ActiveRecord::RecordNotUnique) do
      TaskType.insert_all!([ { key: "feature", name: "Duplicate", workflow_id: workflow.id,
        created_at: Time.current, updated_at: Time.current } ])
    end
  end

  test "enforces unique repository identities in the database" do
    project = create_project

    assert_raises(ActiveRecord::RecordNotUnique) do
      Project.insert_all!([ { name: "Duplicate", remote_url: "https://example.test/test/duplicate.git",
        repository_identity: project.repository_identity, default_branch: "main", created_at: Time.current,
        updated_at: Time.current } ])
    end
  end

  test "enforces one task per non-empty owner in the database" do
    first = create_task
    second = create_task
    first.update_columns(owner_id: "session")

    assert_raises(ActiveRecord::RecordNotUnique) { second.update_columns(owner_id: "session") }
    assert_nil second.reload.owner_id
  end

  test "enforces scoped non-null task creation keys in the database" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    first = create_task(project:, workflow:, task_type:, title: "First")
    second = create_task(project:, workflow:, task_type:, title: "Second")
    first.update_columns(creation_key: "request:fix:sha256:abc")

    assert_raises(ActiveRecord::RecordNotUnique) do
      second.update_columns(creation_key: "request:fix:sha256:abc")
    end

    other_project = create_task(workflow:, task_type:, title: "Other project")
    other_type = create_task_type(workflow:)
    other_type_task = create_task(project:, workflow:, task_type: other_type, title: "Other type")
    assert other_project.update_columns(creation_key: "request:fix:sha256:abc")
    assert other_type_task.update_columns(creation_key: "request:fix:sha256:abc")

    assert create_task(project:, workflow:, task_type:, title: "No key").creation_key.nil?
    assert create_task(project:, workflow:, task_type:, title: "Another null key").creation_key.nil?
  end

  test "defines every domain foreign key" do
    foreign_keys = DOMAIN_TABLES.flat_map do |table|
      ActiveRecord::Base.connection.foreign_keys(table).map do |foreign_key|
        [ table, foreign_key.options.fetch(:column), foreign_key.to_table ]
      end
    end

    assert_equal [
      [ "task_dependencies", "blocker_id", "tasks" ],
      [ "task_dependencies", "task_id", "tasks" ],
      [ "task_types", "workflow_id", "workflows" ],
      [ "tasks", "parent_id", "tasks" ],
      [ "tasks", "project_id", "projects" ],
      [ "tasks", "task_type_id", "task_types" ],
      [ "tasks", "workflow_id", "workflows" ]
    ], foreign_keys.sort
  end

  test "rejects invalid status and negative claim version in the database" do
    task = build_task

    assert_raises(ActiveRecord::StatementInvalid) { task.update_columns(status: "unknown") }
    assert_raises(ActiveRecord::StatementInvalid) { task.update_columns(claim_version: -1) }
  end

  test "enforces task foreign keys" do
    task = build_task

    assert_raises(ActiveRecord::InvalidForeignKey) { task.update_columns(project_id: -1) }
  end

  test "rejects a task as its own parent in the database" do
    task = build_task

    assert_raises(ActiveRecord::StatementInvalid) { task.update_columns(parent_id: task.id) }
  end

  test "rejects a task blocking itself in the database" do
    task = build_task

    assert_raises(ActiveRecord::StatementInvalid) do
      TaskDependency.insert_all!([ { task_id: task.id, blocker_id: task.id } ])
    end
  end

  test "enforces one dependency per task and blocker pair" do
    project = create_project
    task = create_task(project:)
    blocker = create_task(project:)
    TaskDependency.create!(task:, blocker:)

    assert_raises(ActiveRecord::RecordInvalid) do
      TaskDependency.create!(task:, blocker:)
    end
  end

  test "exposes parent and blocking associations" do
    project = create_project
    parent = create_task(project:)
    blocker = create_task(project:)
    task = create_task(project:, parent:)
    TaskDependency.create!(task:, blocker:)

    assert_equal [ task ], parent.children.to_a
    assert_equal [ blocker ], task.blockers.to_a
    assert_equal [ task ], blocker.blocked_tasks.to_a
  end

  private

  def build_task(parent: nil)
    create_task(parent:)
  end
end
