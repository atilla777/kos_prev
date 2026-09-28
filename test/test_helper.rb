ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all

    def valid_workflow_definition
      {
        "steps" => [
          {
            "id" => "work", "name" => "Work", "instruction" => "Do the work.",
            "outcomes" => {
              "done" => { "next_step" => "review" },
              "question" => { "pause" => "needs_human" },
              "blocked" => { "pause" => "blocked" }
            }
          },
          {
            "id" => "review", "name" => "Review", "instruction" => "Review the work.",
            "outcomes" => {
              "approved" => { "complete_task" => true },
              "changes_requested" => { "next_step" => "work" }
            }
          }
        ]
      }
    end

    def create_project(name: "Project", remote_url: nil)
      remote_url ||= "https://example.test/test/#{name.parameterize}-#{SecureRandom.hex(6)}.git"
      Project.create!(name:, remote_url:, repository_identity: RepositoryIdentity.normalize(remote_url),
        default_branch: "main")
    end

    def create_workflow(key: nil, revision: 1, definition: valid_workflow_definition, name: "Workflow", **)
      key ||= "workflow-#{SecureRandom.hex(6)}"
      Workflow.create!(key:, name:, revision:, definition_json: definition)
    end

    def create_task_plan(project: nil, key: nil, title: "Plan")
      TaskPlan.create!(project: project || create_project, key: key || "plan-#{SecureRandom.hex(6)}", title:)
    end

    def create_task(project: nil, task_plan: nil, workflow: nil, key: nil, current_step: nil, title: "Task", **)
      task_plan ||= create_task_plan(project:)
      workflow ||= create_workflow
      Task.create!(task_plan:, workflow:, key: key || "task-#{SecureRandom.hex(6)}", title:,
        description_markdown: "Description", current_step: current_step || workflow.first_step_id)
    end

    def plan_task(key:, workflow:, blockers: [], title: nil)
      {
        "key" => key,
        "title" => title || key.titleize,
        "description_markdown" => "Do #{key}",
        "workflow_key" => workflow.key,
        "blocker_keys" => blockers
      }
    end
  end
end
