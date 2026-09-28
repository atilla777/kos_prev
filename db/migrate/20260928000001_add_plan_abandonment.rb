class AddPlanAbandonment < ActiveRecord::Migration[8.1]
  PLAN_STATUSES = %w[active abandoned].freeze
  TASK_STATUSES = %w[pending active needs_human blocked completed abandoned].freeze

  def up
    add_column :task_plans, :status, :string, null: false, default: "active"
    add_column :task_plans, :version, :integer, null: false, default: 0
    add_check_constraint :task_plans, "version >= 0", name: "task_plans_nonnegative_version"
    add_check_constraint :task_plans,
      "status IN (#{PLAN_STATUSES.map { |status| connection.quote(status) }.join(', ')})",
      name: "task_plans_status"

    remove_check_constraint :tasks, name: "tasks_status"
    add_check_constraint :tasks,
      "status IN (#{TASK_STATUSES.map { |status| connection.quote(status) }.join(', ')})",
      name: "tasks_status"
  end

  def down
    if select_value("SELECT 1 FROM tasks WHERE status = 'abandoned' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "cannot remove abandonment while abandoned tasks exist"
    end

    remove_check_constraint :tasks, name: "tasks_status"
    add_check_constraint :tasks,
      "status IN (#{(TASK_STATUSES - [ "abandoned" ]).map { |status| connection.quote(status) }.join(', ')})",
      name: "tasks_status"

    remove_check_constraint :task_plans, name: "task_plans_status"
    remove_check_constraint :task_plans, name: "task_plans_nonnegative_version"
    remove_column :task_plans, :version
    remove_column :task_plans, :status
  end
end
