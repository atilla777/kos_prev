require "test_helper"
require "digest"
require_relative "../support/installed_scheduler_harness"
require_relative "../support/lifecycle_scheduler_cli"

class InstalledSchedulerExecutionTest < ActiveSupport::TestCase
  CHILDREN = [
    { "key" => "delivery", "title" => "Deliver behavior", "description_markdown" => "Implement it",
      "blocker_keys" => [] }
  ].freeze

  test "installed built-in commands schedule complete workflows by mode and tier" do
    BuiltInCatalog.install!
    lifecycle = TaskLifecycle.new
    project = create_project(name: "installed scheduler")
    development = lifecycle.create!(project:, task_type: TaskType.find_by!(key: "development"),
      title: "Development", description_markdown: "Schedule development")
    cli = LifecycleSchedulerCli.new(project:, lifecycle:,
      session_ids: %w[development-owner fix-owner brief-owner])
    main_calls = []
    child_calls = []
    review_attempts = Hash.new(0)

    main_runner = lambda do |task_id, owner_id:, command:, model:|
      task = Task.find(task_id)
      assert_equal owner_id, task.owner_id
      main_calls << [ command, model, task.current_step, task.owner_id ]
      lifecycle.report_attempt!(task_id:, owner_id:, claim_version: task.claim_version,
        step: task.current_step, outcome: "specified", artifact: "# Brief")
    end
    child_runner = lambda do |tier:, prompt:, owner_id:, profile:, model:|
      task = Task.find(Integer(prompt, 10))
      assert_equal owner_id, task.owner_id
      step = task.current_step
      type = task.task_type.key
      child_calls << [ type, step, tier, prompt, profile, model, task.owner_id ]
      review_attempts[type] += 1 if step == "review"
      outcome = if type == "development" && step == "review" && review_attempts[type] == 1
        "changes_requested"
      else
        successful_outcome(type, step)
      end
      graph = { "children" => CHILDREN } if type == "brief" && step == "review"
      if type == "brief" && step == "publish"
        BriefTaskGraph.new.materialize!(parent_id: task.id, owner_id: task.owner_id,
          claim_version: task.claim_version, children: CHILDREN)
      end
      lifecycle.report_attempt!(task_id: task.id, owner_id:, claim_version: task.claim_version,
        step:, outcome:, artifact: "# #{step}",
        required_checks: ("passed" if step == "implement"), brief_graph: graph)
      "ignored child claim"
    end

    InstalledSchedulerHarness.install do |config_home|
      scheduler = InstalledSchedulerHarness.new(config_home:, cli:, main_runner:, subagent_runner: child_runner)
      results = [
        scheduler.run(command: "kos", project_id: project.id),
        scheduler.run(command: "kos-fix", project_id: project.id, arguments: "exact fix request\n"),
        scheduler.run(command: "kos-brief", project_id: project.id, arguments: "exact brief request\n")
      ]

      assert_equal %w[completed completed completed], results.map(&:reason)
    end

    assert_equal [ [ "kos-brief", "openai/gpt-5.6-sol", "brief", "brief-owner" ] ], main_calls
    assert_equal 3, cli.operations.count { |operation| operation == [ :session_id ] }
    assert_equal [ "exact fix request\n", "exact brief request\n" ], cli.requests
    assert_equal [ "completed", "completed", "completed" ],
      [ development, Task.find_by!(creation_key: request_key("fix", "exact fix request\n")),
        Task.find_by!(creation_key: request_key("brief", "exact brief request\n")) ].map { |task| task.reload.status }
    assert_equal [
      %w[development plan advanced], %w[development implement standard],
      %w[development document standard], %w[development review advanced],
      %w[development implement standard], %w[development document standard],
      %w[development review advanced], %w[development publish standard],
      %w[fix diagnose advanced], %w[fix plan advanced], %w[fix implement standard],
      %w[fix document standard], %w[fix review advanced], %w[fix publish standard],
      %w[brief review advanced], %w[brief publish standard]
    ], child_calls.map { |type, step, tier,| [ type, step, tier ] }
    assert child_calls.all? { |_, _, _, prompt, _, _, _| prompt.match?(/\A\d+\z/) }
    assert child_calls.all? do |_, _, tier, _, profile, model, _|
      profile == "kos-step-#{tier}" && model == (tier == "standard" ? "openai/gpt-5.6-terra" : "openai/gpt-5.6-sol")
    end
    assert_equal %w[development-owner fix-owner brief-owner], child_calls.map(&:last).uniq
    assert_equal 1, Task.find_by!(creation_key: request_key("brief", "exact brief request\n")).children.count
    assert_empty cli.operations.map(&:first) - %i[session_id resumable claim_next create_or_get show resume]
  end

  private

  def successful_outcome(type, step)
    {
      "development" => { "plan" => "planned", "implement" => "implemented", "document" => "documented",
        "review" => "approved", "publish" => "published" },
      "fix" => { "diagnose" => "diagnosed", "plan" => "planned", "implement" => "implemented",
        "document" => "documented", "review" => "approved", "publish" => "published" },
      "brief" => { "review" => "approved", "publish" => "published" }
    }.fetch(type).fetch(step)
  end

  def request_key(kind, request)
    "request:#{kind}:sha256:#{Digest::SHA256.hexdigest(request)}"
  end
end
