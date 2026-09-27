require "test_helper"
require_relative "../support/installed_scheduler_harness"
require_relative "../support/lifecycle_scheduler_cli"

class CustomWorkflowExecutionTest < ActiveSupport::TestCase
  test "installed custom command executes main and subagent steps through pause backward transition and completion" do
    project = create_project
    workflow = create_workflow(name: "Custom delivery", definition: custom_definition)
    task_type = create_task_type(name: "Custom delivery", key: "custom-delivery", workflow:)
    lifecycle = TaskLifecycle.new
    task = lifecycle.create!(project:, task_type:, title: "Custom task", description_markdown: "Execute it")
    cli = LifecycleSchedulerCli.new(project:, lifecycle:, session_ids: %w[custom-owner-1 custom-owner-2])
    main_calls = []
    subagent_calls = []
    publish_attempts = 0
    review_attempts = 0
    main_runner = lambda do |task_id, owner_id:, command:, model:|
      current = Task.find(task_id)
      assert_equal owner_id, current.owner_id
      main_calls << [ current.current_step, current.workflow.step_for(current.current_step).fetch("model_tier"),
        command, model ]
      outcome = if current.current_step == "publish"
        publish_attempts += 1
        publish_attempts == 1 ? "question" : "ready"
      else
        "finished"
      end
      lifecycle.report_attempt!(task_id:, owner_id:, claim_version: current.claim_version,
        step: current.current_step, outcome:, artifact: "# Main #{outcome}",
        message: ("Which direction?" if outcome == "question"))
    end
    subagent_runner = lambda do |tier:, prompt:, owner_id:, profile:, model:|
      current = Task.find(Integer(prompt, 10))
      assert_equal owner_id, current.owner_id
      subagent_calls << [ tier, prompt, current.current_step, profile, model ]
      review_attempts += 1
      outcome = review_attempts == 1 ? "changes_requested" : "approved"
      lifecycle.report_attempt!(task_id: current.id, owner_id:,
        claim_version: current.claim_version, step: current.current_step, outcome:, artifact: "# Review #{outcome}")
    end
    InstalledSchedulerHarness.install do |config_home|
      scheduler = InstalledSchedulerHarness.new(config_home:, cli:, main_runner:, subagent_runner:,
        clock: -> { Time.utc(2026, 9, 27) })
      paused = scheduler.run(command: "kos-task", project_id: project.id, arguments: task_type.key)

      assert_equal "needs_human", paused.reason
      assert_equal "Which direction?", task.reload.pause_message
      completed = scheduler.run(command: "kos-task", project_id: project.id, arguments: task_type.key,
        answer: "Proceed")

      assert_equal "completed", completed.reason
    end
    assert_equal [ [ "publish", "standard", "kos-task", "openai/gpt-5.6-sol" ],
      [ "publish", "standard", "kos-task", "openai/gpt-5.6-sol" ],
      [ "publish", "standard", "kos-task", "openai/gpt-5.6-sol" ],
      [ "finalize", "standard", "kos-task", "openai/gpt-5.6-sol" ] ], main_calls
    assert_equal [ [ "standard", task.id.to_s, "review", "kos-step-standard", "openai/gpt-5.6-terra" ],
      [ "standard", task.id.to_s, "review", "kos-step-standard", "openai/gpt-5.6-terra" ] ], subagent_calls
    assert_equal %w[approved finished], task.reload.accepted_artifacts.values_at("review", "finalize").pluck("outcome")
    assert_nil task.owner_id
  end

  test "custom entry rejects blank and reserved keys before selection" do
    cli = Object.new
    cli.define_singleton_method(:resumable) { |**| raise "selection must not run" }
    scheduler = KosSchedulerHarness.new(cli:, main_runner: ->(*) { }, subagent_runner: ->(**) { })

    [ "", " \n\t", "brief", "development", "fix" ].each do |key|
      assert_raises(ArgumentError) do
        scheduler.run_custom(project_id: 1, task_type_key: key, owner_id: "owner")
      end
    end
  end

  private

  def custom_definition
    {
      "steps" => [
        {
          "id" => "publish", "name" => "Custom main", "execution_mode" => "main", "model_tier" => "standard",
          "instruction" => "Execute custom work.", "artifact_template" => "# Main",
          "outcomes" => {
            "ready" => { "next_step" => "review" }, "question" => { "pause" => "needs_human" }
          }
        },
        {
          "id" => "review", "name" => "Custom subagent", "execution_mode" => "subagent",
          "model_tier" => "standard", "instruction" => "Inspect custom work.", "artifact_template" => "# Review",
          "outcomes" => {
            "changes_requested" => { "next_step" => "publish" }, "approved" => { "next_step" => "finalize" }
          }
        },
        {
          "id" => "finalize", "name" => "Custom completion", "execution_mode" => "main",
          "model_tier" => "standard", "instruction" => "Complete custom work.", "artifact_template" => "# Final",
          "outcomes" => { "finished" => { "complete_task" => true } }
        }
      ]
    }
  end
end
