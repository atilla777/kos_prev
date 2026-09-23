# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_23_010000) do
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

  create_table "task_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_id", null: false
    t.index ["key"], name: "index_task_types_on_key", unique: true
    t.index ["workflow_id"], name: "index_task_types_on_workflow_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.json "accepted_artifacts", default: {}, null: false
    t.integer "claim_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "creation_key"
    t.string "current_step", null: false
    t.text "description_markdown", null: false
    t.text "human_answer"
    t.integer "human_answer_claim_version"
    t.string "human_answer_step"
    t.datetime "lease_expires_at"
    t.string "owner_id"
    t.integer "parent_id"
    t.integer "pause_claim_version"
    t.text "pause_message"
    t.string "pause_step"
    t.integer "project_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "task_type_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_id", null: false
    t.index ["owner_id"], name: "index_tasks_on_owner_id", unique: true, where: "owner_id IS NOT NULL"
    t.index ["parent_id"], name: "index_tasks_on_parent_id"
    t.index ["project_id", "task_type_id", "creation_key"], name: "index_tasks_on_scoped_creation_key", unique: true, where: "creation_key IS NOT NULL"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["task_type_id"], name: "index_tasks_on_task_type_id"
    t.index ["workflow_id"], name: "index_tasks_on_workflow_id"
    t.check_constraint "claim_version >= 0", name: "tasks_claim_version_nonnegative"
    t.check_constraint "parent_id IS NULL OR parent_id != id", name: "tasks_parent_not_self"
    t.check_constraint "status IN ('pending', 'active', 'needs_human', 'blocked', 'completed', 'cancelled')", name: "tasks_status"
  end

  create_table "workflows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "definition_json", null: false
    t.string "name", null: false
  end

  add_foreign_key "task_dependencies", "tasks"
  add_foreign_key "task_dependencies", "tasks", column: "blocker_id"
  add_foreign_key "task_types", "workflows"
  add_foreign_key "tasks", "projects"
  add_foreign_key "tasks", "task_types"
  add_foreign_key "tasks", "tasks", column: "parent_id"
  add_foreign_key "tasks", "workflows"
end
