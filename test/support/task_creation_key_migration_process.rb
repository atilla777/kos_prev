require "active_record"
require "json"

database = ARGV.fetch(0)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database:)
connection = ActiveRecord::Base.connection
connection.execute("PRAGMA foreign_keys = ON")
connection.create_table(:projects) { |table| table.string :name }
connection.create_table(:workflows) { |table| table.json :definition_json }
connection.create_table(:task_types) { |table| table.integer :workflow_id, null: false }
connection.create_table(:tasks) do |table|
  table.integer :project_id, null: false
  table.integer :task_type_id, null: false
  table.integer :workflow_id, null: false
  table.integer :parent_id
end
connection.create_table(:task_dependencies) do |table|
  table.integer :task_id, null: false
  table.integer :blocker_id, null: false
end

connection.execute("INSERT INTO projects (id, name) VALUES (11, 'Project')")
connection.execute("INSERT INTO workflows (id, definition_json) VALUES (12, '{}')")
connection.execute("INSERT INTO task_types (id, workflow_id) VALUES (13, 12)")
connection.execute("INSERT INTO tasks (id, project_id, task_type_id, workflow_id) VALUES (14, 11, 13, 12)")
connection.execute("INSERT INTO tasks (id, project_id, task_type_id, workflow_id, parent_id) VALUES (15, 11, 13, 12, 14)")
connection.execute("INSERT INTO task_dependencies (id, task_id, blocker_id) VALUES (16, 15, 14)")

require_relative "../../db/migrate/20260923010000_add_task_creation_key"

migration = AddTaskCreationKey.new
migration.migrate(:up)
null_rows_before = connection.select_value("SELECT COUNT(*) FROM tasks WHERE creation_key IS NULL")
connection.execute("UPDATE tasks SET creation_key = 'request:fix:sha256:abc' WHERE id = 14")
duplicate_rejected = false
begin
  connection.execute("UPDATE tasks SET creation_key = 'request:fix:sha256:abc' WHERE id = 15")
rescue ActiveRecord::RecordNotUnique
  duplicate_rejected = true
end
ids = connection.select_rows("SELECT id, project_id, task_type_id, workflow_id, parent_id FROM tasks ORDER BY id")
dependency = connection.select_rows("SELECT id, task_id, blocker_id FROM task_dependencies")
migration.migrate(:down)

puts JSON.generate(
  null_rows_before:,
  duplicate_rejected:,
  columns_after_down: connection.columns(:tasks).map(&:name),
  indexes_after_down: connection.indexes(:tasks).map(&:name),
  ids:,
  ids_after_down: connection.select_rows("SELECT id, project_id, task_type_id, workflow_id, parent_id FROM tasks ORDER BY id"),
  dependency:,
  dependency_after_down: connection.select_rows("SELECT id, task_id, blocker_id FROM task_dependencies")
)
