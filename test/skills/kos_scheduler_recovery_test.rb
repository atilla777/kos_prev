require "test_helper"
require_relative "../support/kos_scheduler_harness"

class KosSchedulerRecoveryTest < ActiveSupport::TestCase
  FakeCli = Struct.new(:contexts, :resumes) do
    def context(_task_id)
      contexts.shift || raise("unexpected context read")
    end

    def resume(**arguments)
      resumes << arguments
    end
  end

  test "a child crash stops after one unchanged dispatch" do
    context = active_context
    cli = FakeCli.new([ context, context.deep_dup ], [])
    calls = []
    scheduler = harness(cli:, subagent_runner: lambda { |**arguments|
      calls << arguments
      raise "child crashed"
    })

    result = scheduler.run(task_id: 41, owner_id: "owner")

    assert_equal "unchanged", result.reason
    assert_equal [ { tier: "advanced", prompt: "41" } ], calls
    assert_empty cli.resumes
  end

  test "a rejected report stops after one unchanged child return" do
    context = active_context
    cli = FakeCli.new([ context, context.deep_dup ], [])
    calls = []
    scheduler = harness(cli:, subagent_runner: ->(**arguments) { calls << arguments })

    result = scheduler.run(task_id: 42, owner_id: "owner")

    assert_equal "unchanged", result.reason
    assert_equal 1, calls.length
    assert_empty cli.resumes
  end

  test "an expired unchanged claim is resumed once before one retry" do
    now = Time.utc(2026, 9, 27, 10, 0, 0)
    first = active_context(lease_expires_at: (now + 1.minute).iso8601)
    resumed = active_context(owner_id: "new-owner", claim_version: 2, lease_expires_at: (now + 1.hour).iso8601)
    paused = context(status: "needs_human", claim_version: 3, lease_expires_at: nil)
    cli = FakeCli.new([ first, first.deep_dup, resumed, paused ], [])
    calls = 0
    scheduler = harness(cli:, clock: -> { now }, subagent_runner: lambda { |**|
      calls += 1
      now += 2.minutes if calls == 1
    })

    result = scheduler.run(task_id: 43, owner_id: "new-owner")

    assert_equal "needs_human", result.reason
    assert_equal 2, calls
    assert_equal [ { task_id: 43, owner_id: "new-owner", claim_version: 1, step: "plan" } ], cli.resumes
  end

  test "an expired retry stops without another recovery" do
    now = Time.utc(2026, 9, 27, 10, 0, 0)
    expired = active_context(lease_expires_at: (now - 1.minute).iso8601)
    resumed = active_context(claim_version: 2, lease_expires_at: (now + 1.minute).iso8601)
    cli = FakeCli.new([ expired, resumed, resumed.deep_dup ], [])
    scheduler = harness(cli:, clock: -> { now }, subagent_runner: ->(**) { now += 2.minutes })

    result = scheduler.run(task_id: 44, owner_id: "owner")

    assert_equal "unchanged", result.reason
    assert_equal 1, cli.resumes.length
  end

  test "resume confirmation rejects a wrong owner step fence or lease" do
    now = Time.utc(2026, 9, 27, 10, 0, 0)
    expired = active_context(lease_expires_at: (now - 1.minute).iso8601)
    invalid_resumes = [
      active_context(owner_id: "other", claim_version: 2, lease_expires_at: (now + 1.hour).iso8601),
      active_context(step: "implement", claim_version: 2, lease_expires_at: (now + 1.hour).iso8601),
      active_context(claim_version: 3, lease_expires_at: (now + 1.hour).iso8601),
      active_context(claim_version: 2, lease_expires_at: (now - 1.second).iso8601)
    ]

    invalid_resumes.each do |resumed|
      cli = FakeCli.new([ expired.deep_dup, resumed ], [])
      calls = []
      scheduler = harness(cli:, clock: -> { now }, main_runner: ->(*) { calls << :main },
        subagent_runner: ->(**) { calls << :subagent })

      result = scheduler.run(task_id: 49, owner_id: "owner")

      assert_equal "resume_unconfirmed", result.reason
      assert_empty calls
      assert_equal 1, cli.resumes.length
    end
  end

  test "an unchanged retry stops after one resume and two dispatches" do
    now = Time.utc(2026, 9, 27, 10, 0, 0)
    first = active_context(lease_expires_at: (now + 1.minute).iso8601)
    resumed = active_context(owner_id: "new-owner", claim_version: 2, lease_expires_at: (now + 1.hour).iso8601)
    cli = FakeCli.new([ first, first.deep_dup, resumed, resumed.deep_dup ], [])
    calls = 0
    scheduler = harness(cli:, clock: -> { now }, subagent_runner: lambda { |**|
      calls += 1
      now += 2.minutes if calls == 1
    })

    result = scheduler.run(task_id: 48, owner_id: "new-owner")

    assert_equal "unchanged", result.reason
    assert_equal 2, calls
    assert_equal 1, cli.resumes.length
  end

  test "an authoritative transition continues to the next step" do
    plan = active_context
    implement = active_context(step: "implement", claim_version: 2, execution_mode: "main", model_tier: "standard")
    completed = context(status: "completed", step: "implement", claim_version: 3, lease_expires_at: nil,
      execution_mode: "main", model_tier: "standard")
    cli = FakeCli.new([ plan, implement, completed ], [])
    main_calls = []
    child_calls = []
    scheduler = harness(cli:, main_runner: ->(task_id) { main_calls << task_id },
      subagent_runner: ->(**arguments) { child_calls << arguments })

    result = scheduler.run(task_id: 45, owner_id: "owner")

    assert_equal "completed", result.reason
    assert_equal [ { tier: "advanced", prompt: "45" } ], child_calls
    assert_equal [ 45 ], main_calls
  end

  test "new current-step evidence is authoritative progress" do
    before = active_context
    evidenced = active_context(artifacts: [ { "step" => "plan", "outcome" => "planned",
      "accepted_claim_version" => 1, "reconstructed" => false } ])
    completed = context(status: "completed", claim_version: 2, lease_expires_at: nil)
    cli = FakeCli.new([ before, evidenced, completed ], [])
    calls = []
    scheduler = harness(cli:, subagent_runner: ->(**arguments) { calls << arguments })

    result = scheduler.run(task_id: 46, owner_id: "owner")

    assert_equal "completed", result.reason
    assert_equal 2, calls.length
  end

  test "pause cancellation and completion stop without dispatch" do
    %w[needs_human blocked cancelled completed].each do |status|
      cli = FakeCli.new([ context(status:, lease_expires_at: nil) ], [])
      calls = []
      scheduler = harness(cli:, main_runner: ->(*) { calls << :main },
        subagent_runner: ->(**) { calls << :subagent })

      result = scheduler.run(task_id: 47, owner_id: "owner")

      assert_equal status, result.reason
      assert_empty calls
      assert_empty cli.resumes
    end
  end

  private

  def harness(cli:, main_runner: ->(*) { }, subagent_runner: ->(**) { }, clock: -> { Time.utc(2026, 9, 27) })
    KosSchedulerHarness.new(cli:, main_runner:, subagent_runner:, clock:)
  end

  def active_context(**overrides)
    context(**overrides)
  end

  def context(status: "active", step: "plan", owner_id: "owner", claim_version: 1,
    lease_expires_at: Time.utc(2026, 9, 28).iso8601, execution_mode: "subagent", model_tier: "advanced",
    artifacts: [])
    {
      "task" => {
        "status" => status,
        "current_step" => step,
        "owner_id" => owner_id,
        "claim_version" => claim_version,
        "lease_expires_at" => lease_expires_at
      },
      "step" => {
        "id" => step,
        "execution_mode" => execution_mode,
        "model_tier" => model_tier
      },
      "artifacts" => artifacts
    }
  end
end
