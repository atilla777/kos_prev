class CreateKos < ActiveRecord::Migration[8.1]
  TASK_STATUSES = %w[pending active needs_human blocked completed].freeze

  def change
    create_table :projects do |table|
      table.string :name, null: false
      table.string :repository_identity, null: false, index: { unique: true }
      table.string :remote_url, null: false
      table.string :default_branch, null: false
      table.timestamps
    end

    create_table :workflows do |table|
      table.string :key, null: false
      table.string :name, null: false
      table.integer :revision, null: false
      table.json :definition_json, null: false
      table.datetime :created_at, null: false

      table.index %i[key revision], unique: true
      table.check_constraint "revision > 0", name: "workflows_positive_revision"
    end

    create_table :task_plans do |table|
      table.references :project, null: false, foreign_key: true
      table.string :key, null: false
      table.string :title, null: false
      table.timestamps

      table.index %i[project_id key], unique: true
    end

    create_table :tasks do |table|
      table.references :task_plan, null: false, foreign_key: true
      table.references :workflow, null: false, foreign_key: true
      table.string :key, null: false
      table.string :title, null: false
      table.text :description_markdown, null: false
      table.string :status, null: false, default: "pending"
      table.string :current_step, null: false
      table.string :claim_id
      table.integer :version, null: false, default: 0
      table.json :accepted_results, null: false, default: {}
      table.string :pause_kind
      table.text :pause_message
      table.string :pause_step
      table.text :answer
      table.timestamps

      table.index %i[task_plan_id key], unique: true
      table.check_constraint "version >= 0", name: "tasks_nonnegative_version"
      table.check_constraint "status IN (#{TASK_STATUSES.map { |status| connection.quote(status) }.join(', ')})",
        name: "tasks_status"
    end

    create_table :task_dependencies do |table|
      table.references :task, null: false, foreign_key: true
      table.references :blocker, null: false, foreign_key: { to_table: :tasks }

      table.index %i[task_id blocker_id], unique: true
      table.check_constraint "task_id != blocker_id", name: "task_dependencies_not_self"
    end
  end
end
