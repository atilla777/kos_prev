# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.

ActiveRecord::Schema[8.1].define(version: 2026_09_28_000000) do
  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_branch", null: false
    t.string "name", null: false
    t.string "remote_url", null: false
    t.string "repository_identity", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_identity"], name: "index_projects_on_repository_identity", unique: true
  end

  create_table "task_dependencies", force: :cascade do |t|
    t.integer "blocker_id", null: false
    t.integer "task_id", null: false
    t.index ["blocker_id"], name: "index_task_dependencies_on_blocker_id"
    t.index ["task_id", "blocker_id"], name: "index_task_dependencies_on_task_id_and_blocker_id", unique: true
    t.index ["task_id"], name: "index_task_dependencies_on_task_id"
    t.check_constraint "task_id != blocker_id", name: "task_dependencies_not_self"
  end

  create_table "task_plans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.integer "project_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "key"], name: "index_task_plans_on_project_id_and_key", unique: true
    t.index ["project_id"], name: "index_task_plans_on_project_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.json "accepted_results", default: {}, null: false
    t.text "answer"
    t.string "claim_id"
    t.datetime "created_at", null: false
    t.string "current_step", null: false
    t.text "description_markdown", null: false
    t.string "key", null: false
    t.string "pause_kind"
    t.text "pause_message"
    t.string "pause_step"
    t.string "status", default: "pending", null: false
    t.integer "task_plan_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 0, null: false
    t.integer "workflow_id", null: false
    t.index ["task_plan_id", "key"], name: "index_tasks_on_task_plan_id_and_key", unique: true
    t.index ["task_plan_id"], name: "index_tasks_on_task_plan_id"
    t.index ["workflow_id"], name: "index_tasks_on_workflow_id"
    t.check_constraint "status IN ('pending', 'active', 'needs_human', 'blocked', 'completed')", name: "tasks_status"
    t.check_constraint "version >= 0", name: "tasks_nonnegative_version"
  end

  create_table "workflows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "definition_json", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "revision", null: false
    t.index ["key", "revision"], name: "index_workflows_on_key_and_revision", unique: true
    t.check_constraint "revision > 0", name: "workflows_positive_revision"
  end

  add_foreign_key "task_dependencies", "tasks"
  add_foreign_key "task_dependencies", "tasks", column: "blocker_id"
  add_foreign_key "task_plans", "projects"
  add_foreign_key "tasks", "task_plans"
  add_foreign_key "tasks", "workflows"
end
