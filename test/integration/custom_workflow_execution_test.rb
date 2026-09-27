require "test_helper"
require_relative "../support/kos_scheduler_harness"

class CustomWorkflowExecutionTest < ActiveSupport::TestCase
  class LifecycleCli
    def initialize(project:, task_type:, lifecycle:)
      @project = project
      @task_type = task_type
      @lifecycle = lifecycle
    end

    def resumable(project_id:, task_type_key:)
      assert_selection(project_id, task_type_key)
      @lifecycle.resumable(project: @project, task_type: @task_type).map { |task| envelope(task) }
    end

    def claim_next(project_id:, task_type_key:, owner_id:)
      assert_selection(project_id, task_type_key)
      task = @lifecycle.claim_next!(project: @project, task_type: @task_type, owner_id:)
      envelope(task) if task
    end

    def context(task_id)
      task = Task.find(task_id)
      step = task.workflow.step_for(task.current_step)
      {
        "task" => {
          "id" => task.id, "status" => task.status, "current_step" => task.current_step,
          "owner_id" => task.owner_id, "claim_version" => task.claim_version,
          "lease_expires_at" => task.lease_expires_at&.iso8601
        },
        "step" => step.slice("id", "execution_mode", "model_tier"),
        "artifacts" => task.accepted_artifacts.map do |id, artifact|
          { "step" => id, "outcome" => artifact.fetch("outcome"),
            "accepted_claim_version" => artifact.fetch("accepted_claim_version") }
        end
      }
    end

    def resume(**arguments)
      @lifecycle.resume!(**arguments)
    end

    private

    def assert_selection(project_id, task_type_key)
      raise "wrong project" unless project_id == @project.id
      raise "wrong task type" unless task_type_key == @task_type.key
    end

    def envelope(task)
      { "task" => task.slice(:id, :status, :current_step, :claim_version).stringify_keys }
    end
  end

  test "custom entry executes main and subagent steps through pause backward transition and completion" do
    project = create_project
    workflow = create_workflow(name: "Custom delivery", definition: custom_definition)
    task_type = create_task_type(name: "Custom delivery", key: "custom-delivery", workflow:)
    lifecycle = TaskLifecycle.new
    task = lifecycle.create!(project:, task_type:, title: "Custom task", description_markdown: "Execute it")
    cli = LifecycleCli.new(project:, task_type:, lifecycle:)
    main_calls = []
    subagent_calls = []
    publish_attempts = 0
    review_attempts = 0
    main_runner = lambda do |task_id|
      current = Task.find(task_id)
      main_calls << [ current.current_step, current.workflow.step_for(current.current_step).fetch("model_tier") ]
      outcome = if current.current_step == "publish"
        publish_attempts += 1
        publish_attempts == 1 ? "question" : "ready"
      else
        "finished"
      end
      lifecycle.report_attempt!(task_id:, owner_id: current.owner_id, claim_version: current.claim_version,
        step: current.current_step, outcome:, artifact: "# Main #{outcome}",
        message: ("Which direction?" if outcome == "question"))
    end
    subagent_runner = lambda do |tier:, prompt:|
      current = Task.find(Integer(prompt, 10))
      subagent_calls << [ tier, prompt, current.current_step ]
      review_attempts += 1
      outcome = review_attempts == 1 ? "changes_requested" : "approved"
      lifecycle.report_attempt!(task_id: current.id, owner_id: current.owner_id,
        claim_version: current.claim_version, step: current.current_step, outcome:, artifact: "# Review #{outcome}")
    end
    scheduler = KosSchedulerHarness.new(cli:, main_runner:, subagent_runner:,
      clock: -> { Time.utc(2026, 9, 27) })

    paused = scheduler.run_custom(project_id: project.id, task_type_key: task_type.key, owner_id: "custom-owner-1")

    assert_equal "needs_human", paused.reason
    assert_equal "Which direction?", task.reload.pause_message
    completed = scheduler.run_custom(project_id: project.id, task_type_key: task_type.key, owner_id: "custom-owner-2",
      answer: "Proceed")

    assert_equal "completed", completed.reason
    assert_equal [ [ "publish", "standard" ], [ "publish", "standard" ], [ "publish", "standard" ],
      [ "finalize", "standard" ] ], main_calls
    assert_equal [ [ "standard", task.id.to_s, "review" ], [ "standard", task.id.to_s, "review" ] ], subagent_calls
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
