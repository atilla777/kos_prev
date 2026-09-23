require "test_helper"
require "json"
require "net/http"
require "rbconfig"
require "socket"
require "tempfile"
require "timeout"

class AcceptanceScenariosTest < ActiveSupport::TestCase
  include GitRepositoryHelpers

  test "built in development and fix lifecycles atomically progress through verification" do
    BuiltInCatalog.install!
    lifecycle = TaskLifecycle.new

    {
      "development" => %w[plan implement document review publish verify],
      "fix" => %w[diagnose plan implement document review publish verify]
    }.each do |type_key, expected_steps|
      project = create_project(name: type_key)
      task = lifecycle.create!(project:, task_type: TaskType.find_by!(key: type_key), title: type_key.titleize,
        description_markdown: "Exercise the complete #{type_key} lifecycle")
      task = lifecycle.claim!(task_id: task.id, owner_id: "#{type_key}-owner")

      observed_steps = []
      expected_steps.each do |step|
        observed_steps << task.current_step
        outcome = successful_outcome(type_key, step)
        previous = task.attributes
        artifact = "# #{step.titleize}\n\nAccepted #{outcome}.\n"
        task = lifecycle.report_attempt!(task_id: task.id, owner_id: task.owner_id,
          claim_version: task.claim_version, step:, outcome:, artifact:)

        assert_equal artifact, task.accepted_artifacts.dig(step, "markdown")
        assert_equal outcome, task.accepted_artifacts.dig(step, "outcome")
        assert_equal previous.fetch("claim_version"),
          task.accepted_artifacts.dig(step, "accepted_claim_version")
        assert_equal previous.fetch("claim_version") + 1, task.claim_version
        if step == "publish"
          assert_equal [ "active", "verify", "#{type_key}-owner" ],
            task.values_at(:status, :current_step, :owner_id)
        end
      end

      assert_equal expected_steps, observed_steps
      assert_equal expected_steps, task.accepted_artifacts.keys
      assert_equal [ "completed", "verify", nil, nil ],
        task.values_at(:status, :current_step, :owner_id, :lease_expires_at)
    end
  end

  test "built in correction outcomes route backward and verification failures do not complete" do
    BuiltInCatalog.install!
    routes = {
      "development" => [
        %w[implement plan_invalid plan], %w[document implementation_invalid implement],
        %w[review changes_requested implement], %w[review redesign_required plan],
        %w[publish review_invalid review], %w[publish base_moved implement],
        %w[verify publication_missing publish], %w[verify changes_invalid implement]
      ],
      "fix" => [
        %w[plan diagnosis_invalid diagnose], %w[implement plan_invalid plan],
        %w[document implementation_invalid implement], %w[review changes_requested implement],
        %w[review redesign_required plan], %w[publish review_invalid review],
        %w[publish base_moved implement], %w[verify publication_missing publish],
        %w[verify changes_invalid implement]
      ],
      "brief" => [
        %w[review changes_requested brief], %w[publish review_invalid review],
        %w[publish base_moved brief], %w[publish graph_invalid brief],
        %w[verify publication_missing publish], %w[verify materialization_missing publish],
        %w[verify brief_invalid brief]
      ]
    }

    routes.each do |type_key, cases|
      cases.each_with_index do |(source, outcome, target), index|
        lifecycle = TaskLifecycle.new
        project = create_project(name: "#{type_key}-route-#{index}")
        task = lifecycle.create!(project:, task_type: TaskType.find_by!(key: type_key), title: outcome,
          description_markdown: "Exercise #{outcome}")
        task = lifecycle.claim!(task_id: task.id, owner_id: "#{type_key}-route-#{index}")
        task = advance_to_step(lifecycle, task, type_key, source)

        task = lifecycle.report_attempt!(task_id: task.id, owner_id: task.owner_id,
          claim_version: task.claim_version, step: source, outcome:, artifact: "# #{outcome}\n")

        assert_equal [ "active", target, "#{type_key}-route-#{index}" ],
          task.values_at(:status, :current_step, :owner_id)
        assert_equal outcome, task.accepted_artifacts.dig(source, "outcome")
      end
    end
  end

  test "brief materializes its exact validated graph at publish before verification completes it" do
    BuiltInCatalog.install!
    lifecycle = TaskLifecycle.new
    project = create_project(name: "brief-lifecycle")
    brief = lifecycle.create!(project:, task_type: TaskType.find_by!(key: "brief"), title: "Specify work",
      description_markdown: "Specify an exact graph")
    brief = lifecycle.claim!(task_id: brief.id, owner_id: "brief-owner")
    brief = lifecycle.report_attempt!(task_id: brief.id, owner_id: brief.owner_id,
      claim_version: brief.claim_version, step: "brief", outcome: "specified", artifact: "# Brief\n")
    children = [
      { "key" => "core", "title" => "Core", "description_markdown" => "Build core", "blocker_keys" => [] },
      { "key" => "client", "title" => "Client", "description_markdown" => "Build client",
        "blocker_keys" => [ "core" ] }
    ]
    graph = BriefTaskGraph.new
    validation = graph.validate!(parent: brief, children:)

    assert_no_difference -> { Task.count } do
      assert_raises(TaskLifecycle::Conflict) do
        graph.materialize!(parent_id: brief.id, owner_id: brief.owner_id, claim_version: brief.claim_version,
          expected_digest: validation.fetch(:digest), children:)
      end
    end

    brief = lifecycle.report_attempt!(task_id: brief.id, owner_id: brief.owner_id,
      claim_version: brief.claim_version, step: "review", outcome: "approved", artifact: "# Review\n")
    publish_fence = brief.claim_version
    assert_equal [ "active", "publish", "brief-owner" ], brief.values_at(:status, :current_step, :owner_id)

    assert_difference -> { Task.count }, 2 do
      materialized = graph.materialize!(parent_id: brief.id, owner_id: brief.owner_id,
        claim_version: publish_fence, expected_digest: validation.fetch(:digest), children:)
      assert_equal validation.fetch(:digest), materialized.fetch(:digest)
    end
    assert_equal [ "publish", publish_fence ], brief.reload.values_at(:current_step, :claim_version)
    assert_equal validation.fetch(:digest), graph.observe(parent: brief).fetch(:digest)

    published = lifecycle.report_attempt!(task_id: brief.id, owner_id: brief.owner_id,
      claim_version: publish_fence, step: "publish", outcome: "published", artifact: "# Publication\n")
    assert_equal [ "active", "verify", publish_fence + 1 ],
      published.values_at(:status, :current_step, :claim_version)
    completed = lifecycle.report_attempt!(task_id: brief.id, owner_id: published.owner_id,
      claim_version: published.claim_version, step: "verify", outcome: "verified", artifact: "# Verification\n")

    assert_equal [ "completed", "verify", nil ], completed.values_at(:status, :current_step, :owner_id)
    assert_equal %w[brief review publish verify], completed.accepted_artifacts.keys
    assert completed.children.all? { |child| child.parent_id == completed.id && child.blocker_ids.include?(completed.id) }
  end

  test "a moved base repeats checks and review before one publication commit" do
    with_repository do |repository|
      task, lifecycle = claimed_acceptance_task
      worktree = repository[:root].join("data/worktrees/#{task.project_id}/#{task.id}")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      previous_base = git("rev-parse", "HEAD", chdir: worktree).strip
      File.write(worktree.join("README.md"), "staged task change\n")
      git("add", "README.md", chdir: worktree)
      File.open(worktree.join("README.md"), "a") { |file| file.write("unstaged task change\n") }
      File.write(worktree.join("task.txt"), "task change\n")

      task = run_read_only_plan(lifecycle, task, worktree, repository[:root])
      task = run_implementation(lifecycle, task, worktree, repository[:root], attempt: 1)
      task = run_documentation(lifecycle, task, repository[:root], attempt: 1)
      task = run_read_only_review(lifecycle, task, worktree, repository[:root], attempt: 1)
      assert_equal "publish", task.current_step

      File.write(repository[:publisher].join("base.txt"), "base change\n")
      git("add", "base.txt", chdir: repository[:publisher])
      git("commit", "-m", "Move base", chdir: repository[:publisher])
      git("push", "origin", "main", chdir: repository[:publisher])
      git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main", chdir: repository[:source])
      moved_base = git("rev-parse", "origin/main", chdir: repository[:source]).strip
      assert git_success?("merge-base", "--is-ancestor", previous_base, moved_base, chdir: worktree)

      git("reset", "--mixed", "HEAD", chdir: worktree)
      git("checkout", "--merge", "--detach", moved_base, chdir: worktree)
      task = report(lifecycle, task, "publish", "base_moved")

      assert_equal "implement", task.current_step
      assert_equal moved_base, git("rev-parse", "HEAD", chdir: worktree).strip
      assert_equal "staged task change\nunstaged task change\n", File.read(worktree.join("README.md"))
      assert_equal "task change\n", File.read(worktree.join("task.txt"))
      status = git("status", "--porcelain", chdir: worktree)
      assert_includes status, " M README.md"
      assert_includes status, "?? task.txt"

      task = run_implementation(lifecycle, task, worktree, repository[:root], attempt: 2)
      task = run_documentation(lifecycle, task, repository[:root], attempt: 2)
      task = run_read_only_review(lifecycle, task, worktree, repository[:root], attempt: 2)
      assert_includes task.accepted_artifacts.dig("implement", "markdown"), "Attempt 2"
      assert_includes task.accepted_artifacts.dig("document", "markdown"), "Attempt 2"
      assert_includes task.accepted_artifacts.dig("review", "markdown"), "Attempt 2"
      git("add", "README.md", "task.txt", chdir: worktree)
      git("commit", "-m", "KOS task #{task.id}: #{task.title}", "-m", "KOS-Task: #{task.id}", chdir: worktree)
      candidate = git("rev-parse", "HEAD", chdir: worktree).strip
      git("push", "origin", "#{candidate}:refs/heads/main", chdir: worktree)
      task = report(lifecycle, task, "publish", "published")
      task = report(lifecycle, task, "verify", "verified")

      assert_equal "completed", task.status
      assert_equal candidate, git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main").strip
      assert_equal "3", git("--git-dir", repository[:remote].to_s, "rev-list", "--count", "main").strip
      assert_equal moved_base, git("rev-parse", "#{candidate}^", chdir: worktree).strip
    end
  end

  test "two tasks retain independent ownership artifacts and uncommitted worktrees" do
    with_repository do |repository|
      project = create_project
      workflow = create_workflow(definition: acceptance_workflow_definition)
      task_type = create_task_type(name: "Acceptance", workflow:)
      first = create_task(project:, workflow:, task_type:, current_step: "plan", title: "First")
      second = create_task(project:, workflow:, task_type:, current_step: "plan", title: "Second")
      lifecycle = TaskLifecycle.new

      first_claim = lifecycle.claim_next!(project:, owner_id: "owner-a")
      second_claim = lifecycle.claim_next!(project:, owner_id: "owner-b")
      assert_equal [ first.id, second.id ], [ first_claim.id, second_claim.id ]

      first_worktree = repository[:root].join("data/worktrees/#{project.id}/#{first.id}")
      second_worktree = repository[:root].join("data/worktrees/#{project.id}/#{second.id}")
      git("worktree", "add", "--detach", first_worktree.to_s, "origin/main", chdir: repository[:source])
      git("worktree", "add", "--detach", second_worktree.to_s, "origin/main", chdir: repository[:source])
      File.write(first_worktree.join("first.txt"), "first task\n")
      File.write(second_worktree.join("second.txt"), "second task\n")

      report(lifecycle, first_claim, "plan", "planned", artifact: "# First\n")

      assert_equal [ "implement", "owner-a" ], first.reload.values_at(:current_step, :owner_id)
      assert_equal [ "plan", "owner-b" ], second.reload.values_at(:current_step, :owner_id)
      assert_equal "# First\n", first.reload.accepted_artifacts.dig("plan", "markdown")
      assert_empty second.reload.accepted_artifacts
      assert_includes git("status", "--porcelain", chdir: first_worktree), "first.txt"
      refute_includes git("status", "--porcelain", chdir: first_worktree), "second.txt"
      assert_includes git("status", "--porcelain", chdir: second_worktree), "second.txt"
      refute_includes git("status", "--porcelain", chdir: second_worktree), "first.txt"
      assert_equal "1", git("rev-list", "--count", "HEAD", chdir: first_worktree).strip
      assert_equal "1", git("rev-list", "--count", "HEAD", chdir: second_worktree).strip
    end
  end

  test "review sends ordinary changes to implementation and material redesign to planning" do
    task, lifecycle = claimed_acceptance_task
    task = report(lifecycle, task, "plan", "planned")
    task = report(lifecycle, task, "implement", "implemented")
    task = report(lifecycle, task, "document", "documented")

    task = report(lifecycle, task, "review", "changes_requested")
    assert_equal "implement", task.current_step
    task = report(lifecycle, task, "implement", "implemented")
    task = report(lifecycle, task, "document", "documented")

    task = report(lifecycle, task, "review", "redesign_required")
    assert_equal "plan", task.current_step
  end

  test "publication recovery reuses the candidate before and after push" do
    [ false, true ].each do |push_before_restart|
      with_repository do |repository|
        worktree = repository[:root].join("data/worktrees/1/31")
        git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
        File.write(worktree.join("task.txt"), "published task\n")
        git("add", "task.txt", chdir: worktree)
        reviewed_patch = repository[:root].join("reviewed.patch")
        reviewed_patch.write(git("diff", "--cached", "--binary", chdir: worktree))
        git("commit", "-m", "KOS task 31: Publish", "-m", "KOS-Task: 31", chdir: worktree)
        expected_candidate = git("rev-parse", "HEAD", chdir: worktree).strip
        expected_count = git("rev-list", "--count", "HEAD", chdir: worktree).strip
        git("push", "origin", "#{expected_candidate}:refs/heads/main", chdir: worktree) if push_before_restart

        output, error, status = Open3.capture3(RbConfig.ruby,
          Rails.root.join("test/support/publication_recovery_process.rb").to_s,
          worktree.to_s, repository[:source].to_s, "31", "Publish", JSON.generate([ "task.txt" ]),
          reviewed_patch.to_s)
        assert_predicate status, :success?, error
        recovered = JSON.parse(output)

        assert_equal expected_candidate, recovered.fetch("candidate")
        assert_equal expected_count, recovered.fetch("commit_count")
        assert_equal !push_before_restart, recovered.fetch("pushed")
        assert_equal expected_candidate,
          git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main").strip
        assert_equal "31", git("log", "-1", "--format=%(trailers:key=KOS-Task,valueonly)", chdir: worktree).strip
        assert_empty git("status", "--porcelain", chdir: worktree)
      end
    end
  end

  private

  def create_project(name: "Project", remote_url: "https://example.test/test/project-#{SecureRandom.hex(6)}.git")
    Project.create!(name:, remote_url:, repository_identity: RepositoryIdentity.normalize(remote_url), default_branch: "main")
  end

  def claimed_acceptance_task
    project = create_project
    workflow = create_workflow(definition: acceptance_workflow_definition)
    task_type = create_task_type(name: "Acceptance", workflow:)
    create_task(project:, workflow:, task_type:, current_step: "plan", title: "Publish")
    lifecycle = TaskLifecycle.new
    [ lifecycle.claim_next!(project:, owner_id: "owner"), lifecycle ]
  end

  def report(lifecycle, task, step, outcome, artifact: "# #{step.capitalize}\n")
    lifecycle.report_attempt!(task_id: task.id, owner_id: task.owner_id, claim_version: task.claim_version,
      step:, outcome:, artifact:)
  end

  def successful_outcome(type_key, step)
    {
      "brief" => { "brief" => "specified", "review" => "approved", "publish" => "published",
        "verify" => "verified" },
      "development" => { "plan" => "planned", "implement" => "implemented", "document" => "documented",
        "review" => "approved", "publish" => "published", "verify" => "verified" },
      "fix" => { "diagnose" => "diagnosed", "plan" => "planned", "implement" => "implemented",
        "document" => "documented", "review" => "approved", "publish" => "published",
        "verify" => "verified" }
    }.fetch(type_key).fetch(step)
  end

  def advance_to_step(lifecycle, task, type_key, target)
    until task.current_step == target
      step = task.current_step
      materialize_acceptance_child(task) if type_key == "brief" && step == "publish"
      task = lifecycle.report_attempt!(task_id: task.id, owner_id: task.owner_id,
        claim_version: task.claim_version, step:, outcome: successful_outcome(type_key, step), artifact: "# #{step}\n")
    end
    task
  end

  def materialize_acceptance_child(task)
    children = [ { "key" => "work", "title" => "Work", "description_markdown" => "Implement work",
      "blocker_keys" => [] } ]
    graph = BriefTaskGraph.new
    digest = graph.validate!(parent: task, children:).fetch(:digest)
    graph.materialize!(parent_id: task.id, owner_id: task.owner_id, claim_version: task.claim_version,
      expected_digest: digest, children:)
  end

  def run_read_only_plan(lifecycle, task, worktree, root)
    head = git("rev-parse", "HEAD", chdir: worktree)
    status = git("status", "--porcelain=v2", "--untracked-files=all", "-z", chdir: worktree)
    assert_equal head, git("rev-parse", "HEAD", chdir: worktree)
    assert_equal status, git("status", "--porcelain=v2", "--untracked-files=all", "-z", chdir: worktree)
    report(lifecycle, task, "plan", "planned", artifact: "# Plan\n\nImplement and verify the task.\n")
  end

  def run_implementation(lifecycle, task, worktree, root, attempt:)
    git("diff", "--check", chdir: worktree)
    report(lifecycle, task, "implement", "implemented",
      artifact: "# Implementation\n\nAttempt #{attempt}.\n\n## Checks\n\n`git diff --check`: passed.\n")
  end

  def run_documentation(lifecycle, task, root, attempt:)
    report(lifecycle, task, "document", "documented",
      artifact: "# Documentation\n\nAttempt #{attempt}: no observable behavior change.\n")
  end

  def run_read_only_review(lifecycle, task, worktree, root, attempt:)
    head = git("rev-parse", "HEAD", chdir: worktree)
    status = git("status", "--porcelain=v2", "--untracked-files=all", "-z", chdir: worktree)
    output, error, review_status = Open3.capture3(RbConfig.ruby,
      Rails.root.join("test/support/read_only_review_process.rb").to_s,
      worktree.to_s, JSON.generate([ "README.md", "task.txt" ]))
    assert_predicate review_status, :success?, error
    review = JSON.parse(output)
    assert_equal [ "README.md", "task.txt" ], review.fetch("paths")
    assert_includes review.fetch("tracked_patch"), "staged task change"
    assert_equal "staged task change\nunstaged task change\n", review.dig("contents", "README.md")
    assert_equal "task change\n", review.dig("contents", "task.txt")
    assert_equal head, git("rev-parse", "HEAD", chdir: worktree)
    assert_equal status, git("status", "--porcelain=v2", "--untracked-files=all", "-z", chdir: worktree)
    report(lifecycle, task, "review", "approved", artifact: "# Review\n\nAttempt #{attempt}: approved.\n")
  end
end

class RestartRecoveryScenarioTest < ActiveSupport::TestCase
  test "task state and accepted artifact survive restart without a local task artifact directory" do
    with_running_system do |system|
      resources = create_resources(system)
      claim = run_kos_json(system, "task", "claim-next", "--project-id", resources.fetch(:project_id).to_s,
        "--task-type-key", "development", "--owner-id", "session-before-restart")
      task = claim.fetch("task")
      artifact = temporary_artifact("# Plan\n\nReady.\n")
      advanced = run_kos_json(system, "task", "report-attempt", task.fetch("id").to_s,
        "--owner-id", "session-before-restart", "--claim-version", "1", "--step", "plan", "--outcome", "planned",
        "--artifact-file", artifact.path)
      assert_equal "implement", advanced.dig("task", "current_step")
      refute_predicate system.fetch(:data_home).join("tasks"), :exist?

      restart_server(system)
      shown = run_kos_json(system, "task", "show", task.fetch("id").to_s)
      resumed = run_kos_json(system, "task", "resume", task.fetch("id").to_s,
        "--owner-id", "session-after-restart", "--claim-version", "2", "--step", "implement",
        "--takeover-confirmed")
      accepted = run_kos_json(system, "task", "artifact", task.fetch("id").to_s, "--step", "plan")

      assert_equal [ "active", "implement", 2 ], shown.fetch("task").values_at("status", "current_step", "claim_version")
      assert_equal resources.fetch(:workflow_id), shown.dig("task", "workflow_id")
      assert_equal "# Plan\n\nReady.\n", accepted.fetch("markdown")
      assert_equal "planned", accepted.fetch("outcome")
      refute_predicate system.fetch(:data_home).join("tasks"), :exist?
      assert_equal [ "session-after-restart", "implement", 3 ],
        resumed.fetch("task").values_at("owner_id", "current_step", "claim_version")
    end
  end

  test "a dropped report response is recovered by show without a duplicate transition" do
    with_running_system do |system|
      resources = create_resources(system)
      claim = run_kos_json(system, "task", "claim-next", "--project-id", resources.fetch(:project_id).to_s,
        "--task-type-key", "development", "--owner-id", "session")
      task_id = claim.dig("task", "id")
      artifact = temporary_artifact("# Plan\n\nReady.\n")
      proxy = dropping_proxy(system.fetch(:port))

      _output, error, status = run_kos(system, "task", "report-attempt", task_id.to_s,
        "--owner-id", "session", "--claim-version", "1", "--step", "plan", "--outcome", "planned",
        "--artifact-file", artifact.path,
        api_url: proxy.fetch(:url))
      joined = proxy.fetch(:thread).join(5)
      cleanup_proxy(proxy)
      assert joined, "response-dropping proxy did not finish"
      assert_empty proxy.fetch(:errors)
      assert_equal 3, status.exitstatus
      assert_equal "transport_error", JSON.parse(error).fetch("error")

      shown = run_kos_json(system, "task", "show", task_id.to_s)
      assert_equal [ "active", "implement", "session", 2 ],
        shown.fetch("task").values_at("status", "current_step", "owner_id", "claim_version")

      output, stale_error, stale_status = run_kos(system, "task", "report-attempt", task_id.to_s,
        "--owner-id", "session", "--claim-version", "1", "--step", "plan", "--outcome", "planned",
        "--artifact-file", artifact.path)
      assert_equal 1, stale_status.exitstatus
      assert_empty stale_error
      assert_equal "conflict", JSON.parse(output).fetch("error")
      assert_equal 2, run_kos_json(system, "task", "show", task_id.to_s).dig("task", "claim_version")
    end
  end

  test "fix creation recovery observes its durable owner without a duplicate task" do
    with_running_system do |system|
      project = run_kos_json(system, "project", "create", "--name", "Fix recovery", "--remote-url",
        "https://example.test/test/fix-recovery.git", "--default-branch", "main").fetch("project")
      Tempfile.create([ "fix", ".md" ]) do |description_file|
        description_file.write("# Problem\n\nThe command returns the wrong status.\n")
        description_file.flush

        unreachable_port = available_port
        _output, error, status = run_kos(system, "task", "create-and-claim", "--project-id", project.fetch("id").to_s,
          "--task-type-key", "fix", "--title", "Wrong command status", "--description-file",
          description_file.path, "--owner-id", "durable-fix-owner", api_url: "http://127.0.0.1:#{unreachable_port}")
        assert_equal 3, status.exitstatus
        assert_equal "transport_error", JSON.parse(error).fetch("error")
        assert_empty run_kos(system, "task", "show-owned", "--project-id", project.fetch("id").to_s,
          "--owner-id", "durable-fix-owner").first

        proxy = dropping_proxy(system.fetch(:port))
        _output, error, status = run_kos(system, "task", "create-and-claim", "--project-id", project.fetch("id").to_s,
          "--task-type-key", "fix", "--title", "Wrong command status", "--description-file",
          description_file.path, "--owner-id", "durable-fix-owner", api_url: proxy.fetch(:url))
        joined = proxy.fetch(:thread).join(5)
        cleanup_proxy(proxy)
        assert joined, "response-dropping proxy did not finish"
        assert_empty proxy.fetch(:errors)
        assert_equal 3, status.exitstatus
        assert_equal "transport_error", JSON.parse(error).fetch("error")

        observed = run_kos_json(system, "task", "show-owned", "--project-id", project.fetch("id").to_s,
          "--owner-id", "durable-fix-owner")
        assert_equal [ "fix", "active", "diagnose", 1 ],
          [ observed.dig("task", "task_type_key"), observed.dig("task", "status"),
            observed.dig("task", "current_step"), observed.dig("task", "claim_version") ]

        recovered = run_kos_json(system, "task", "create-and-claim", "--project-id", project.fetch("id").to_s,
          "--task-type-key", "fix", "--title", "Wrong command status", "--description-file",
          description_file.path, "--owner-id", "durable-fix-owner")
        assert_equal observed.dig("task", "id"), recovered.dig("task", "id")
        resumable = run_kos_json(system, "task", "resumable", "--project-id", project.fetch("id").to_s,
          "--task-type-key", "fix")
        assert_equal [ observed.dig("task", "id") ], resumable.map { |entry| entry.dig("task", "id") }
      end
    end
  end

  test "a paused question and answer survive repeated interruption in server state" do
    with_running_system do |system|
      resources = create_resources(system)
      claim = run_kos_json(system, "task", "claim-next", "--project-id", resources.fetch(:project_id).to_s,
        "--task-type-key", "development", "--owner-id", "session-before-question").fetch("task")
      question = "Which supported behavior should the implementation preserve?"
      question_artifact = temporary_artifact("# Plan\n\n## Question\n\n#{question}\n")

      paused = run_kos_json(system, "task", "report-attempt", claim.fetch("id").to_s,
        "--owner-id", "session-before-question", "--claim-version", "1", "--step", "plan",
        "--outcome", "needs_human", "--artifact-file", question_artifact.path, "--message", question).fetch("task")
      assert_equal [ "needs_human", "plan", nil, 2 ],
        paused.values_at("status", "current_step", "owner_id", "claim_version")

      answer = "# Human answer\n\n## Question\n#{question}\n\n## Answer\nPreserve the documented CLI behavior.\n"
      answer_file = temporary_artifact(answer)
      restart_server(system)

      resumable = run_kos_json(system, "task", "resumable", "--project-id", resources.fetch(:project_id).to_s,
        "--task-type-key", "development")
      assert_equal [ claim.fetch("id") ], resumable.map { |entry| entry.dig("task", "id") }
      context = run_kos_json(system, "task", "context", claim.fetch("id").to_s)
      assert_equal question, context.dig("pause", "message")

      resumed = run_kos_json(system, "task", "resume", claim.fetch("id").to_s,
        "--owner-id", "session-after-answer", "--claim-version", "2", "--step", "plan",
        "--answer-file", answer_file.path).fetch("task")
      assert_equal [ "active", "plan", "session-after-answer", 3 ],
        resumed.values_at("status", "current_step", "owner_id", "claim_version")
      restart_server(system)
      assert_equal answer, run_kos_json(system, "task", "context", claim.fetch("id").to_s).dig("pause", "answer")
      resumed = run_kos_json(system, "task", "resume", claim.fetch("id").to_s,
        "--owner-id", "session-after-second-restart", "--claim-version", "3", "--step", "plan",
        "--takeover-confirmed").fetch("task")
      assert_equal [ "active", "plan", "session-after-second-restart", 4 ],
        resumed.values_at("status", "current_step", "owner_id", "claim_version")
      assert_equal answer, run_kos_json(system, "task", "context", claim.fetch("id").to_s).dig("pause", "answer")

      plan_artifact = temporary_artifact("# Plan\n\nReady.\n")
      advanced = run_kos_json(system, "task", "report-attempt", claim.fetch("id").to_s,
        "--owner-id", "session-after-second-restart", "--claim-version", "4", "--step", "plan",
        "--outcome", "planned", "--artifact-file", plan_artifact.path).fetch("task")
      assert_equal "implement", advanced.fetch("current_step")
    end
  end

  test "a dropped materialization response is recovered through the public child graph" do
    with_running_system do |system|
      project = run_kos_json(system, "project", "create", "--name", "Brief recovery", "--remote-url",
        "https://example.test/test/brief-recovery.git", "--default-branch", "main").fetch("project")
      Tempfile.create([ "brief", ".md" ]) do |description_file|
        description_file.write("Specify recovery\n")
        description_file.flush
        claim = run_kos_json(system, "task", "create-and-claim", "--project-id", project.fetch("id").to_s,
          "--task-type-key", "brief", "--title", "Recovery brief", "--description-file", description_file.path,
          "--owner-id", "brief-owner").fetch("task")
        task_id = claim.fetch("id")
        claim = run_kos_json(system, "task", "report-attempt", task_id.to_s, "--owner-id", "brief-owner",
          "--claim-version", claim.fetch("claim_version").to_s, "--step", "brief", "--outcome", "specified",
          "--artifact-file", description_file.path)
          .fetch("task")
        claim = run_kos_json(system, "task", "report-attempt", task_id.to_s, "--owner-id", "brief-owner",
          "--claim-version", claim.fetch("claim_version").to_s, "--step", "review", "--outcome", "approved",
          "--artifact-file", description_file.path)
          .fetch("task")

        Tempfile.create([ "children", ".json" ]) do |graph_file|
          graph_file.write(JSON.generate(children: [ {
            key: "child", title: "Recovered child", description_markdown: "Implement", blocker_keys: []
          } ]))
          graph_file.flush
          digest = run_kos_json(system, "task", "validate-children", task_id.to_s,
            "--definition-file", graph_file.path).fetch("digest")
          proxy = dropping_proxy(system.fetch(:port))

          _output, error, status = run_kos(system, "task", "materialize-children", task_id.to_s,
            "--definition-file", graph_file.path, "--owner-id", "brief-owner", "--claim-version",
            claim.fetch("claim_version").to_s, "--expected-digest", digest, api_url: proxy.fetch(:url))
          joined = proxy.fetch(:thread).join(5)
          cleanup_proxy(proxy)
          assert joined, "response-dropping proxy did not finish"
          assert_empty proxy.fetch(:errors)
          assert_equal 3, status.exitstatus
          assert_equal "transport_error", JSON.parse(error).fetch("error")

          output, retry_error, retry_status = run_kos(system, "task", "materialize-children", task_id.to_s,
            "--definition-file", graph_file.path, "--owner-id", "brief-owner", "--claim-version",
            claim.fetch("claim_version").to_s, "--expected-digest", digest)
          assert_equal 1, retry_status.exitstatus
          assert_empty retry_error
          assert_equal "conflict", JSON.parse(output).fetch("error")

          observed = run_kos_json(system, "task", "children", task_id.to_s)
          assert_equal digest, observed.fetch("digest")
          assert_equal [ "Recovered child" ], observed.fetch("children").map { |entry| entry.dig("task", "title") }
        end
      end
    end
  end

  private

  def with_running_system
    Dir.mktmpdir("kos-system") do |directory|
      root = Pathname(directory)
      system = {
        data_home: root.join("data"), token: "integration-secret",
        log: root.join("server.log"), pid: nil
      }
      prepare_database(system)
      start_server(system)
      yield system
    ensure
      stop_server(system) if system
    end
  end

  def prepare_database(system)
    _output, error, status = Open3.capture3(server_environment(system), Rails.root.join("bin/rails").to_s, "db:prepare")
    assert_predicate status, :success?, error
  end

  def start_server(system)
    3.times do
      system[:port] = available_port
      system[:api_url] = "http://127.0.0.1:#{system.fetch(:port)}"
      system[:pid] = Process.spawn(server_environment(system), Rails.root.join("bin/rails").to_s, "server",
        "--binding", "127.0.0.1", "--port", system.fetch(:port).to_s,
        "--pid", system.fetch(:data_home).join("server.pid").to_s,
        out: system.fetch(:log).to_s, err: system.fetch(:log).to_s, pgroup: true)
      started = Timeout.timeout(15) do
        loop do
          if Process.waitpid(system.fetch(:pid), Process::WNOHANG)
            system[:pid] = nil
            break false
          end
          response = Net::HTTP.start("127.0.0.1", system.fetch(:port), open_timeout: 0.2, read_timeout: 0.2) do |http|
            http.get("/up")
          end
          break true if response.is_a?(Net::HTTPSuccess)
        rescue Errno::ECONNREFUSED, EOFError, Net::OpenTimeout, Net::ReadTimeout
          sleep 0.05
        end
      end
      return if started
    end
    flunk("Rails server exited before binding:\n#{File.read(system.fetch(:log))}")
  rescue Timeout::Error
    flunk("Rails server did not start:\n#{File.read(system.fetch(:log))}")
  end

  def stop_server(system)
    return unless system[:pid]

    Process.kill("TERM", -system.fetch(:pid))
    Timeout.timeout(10) { Process.wait(system.fetch(:pid)) }
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  rescue Timeout::Error
    Process.kill("KILL", -system.fetch(:pid))
    Process.wait(system.fetch(:pid))
  ensure
    system[:pid] = nil
  end

  def restart_server(system)
    stop_server(system)
    start_server(system)
  end

  def server_environment(system)
    {
      "RAILS_ENV" => "development", "KOS_API_TOKEN" => system.fetch(:token),
      "KOS_DATA_HOME" => system.fetch(:data_home).to_s, "RAILS_LOG_TO_STDOUT" => "1",
      "DATABASE_URL" => nil
    }
  end

  def create_resources(system)
    project = run_kos_json(system, "project", "create", "--name", "Acceptance", "--remote-url",
      "https://example.test/test/acceptance.git", "--default-branch", "main").fetch("project")
    Tempfile.create([ "task", ".md" ]) do |description_file|
      description_file.write("Integration task\n")
      description_file.flush
      task = run_kos_json(system, "task", "create", "--project-id", project.fetch("id").to_s,
        "--task-type-key", "development", "--title", "Integration", "--description-file", description_file.path)
        .fetch("task")
      return { project_id: project.fetch("id"), workflow_id: task.fetch("workflow_id") }
    end
  end

  def run_kos_json(system, *arguments)
    output, error, status = run_kos(system, *arguments)
    assert_predicate status, :success?, "#{arguments.join(" ")} failed:\n#{output}#{error}"
    JSON.parse(output)
  end

  def run_kos(system, *arguments, api_url: system.fetch(:api_url))
    environment = {
      "RUBYOPT" => nil, "RUBYLIB" => nil, "KOS_API_URL" => api_url,
      "KOS_API_TOKEN" => system.fetch(:token)
    }
    Open3.capture3(environment, RbConfig.ruby, "--disable-gems", Rails.root.join("bin/kos").to_s, *arguments)
  end

  def temporary_artifact(markdown)
    file = Tempfile.new([ "attempt", ".md" ])
    file.binmode
    file.write(markdown)
    file.flush
    file
  end

  def dropping_proxy(upstream_port)
    server = TCPServer.new("127.0.0.1", 0)
    errors = Queue.new
    thread = Thread.new do
      client = nil
      upstream = nil
      Timeout.timeout(5) do
        client = server.accept
        upstream = TCPSocket.new("127.0.0.1", upstream_port)
        request = read_http_message(client)
        upstream.write(request)
        read_http_message(upstream)
      end
    rescue StandardError => error
      errors << error unless error.is_a?(IOError) && server.closed?
    ensure
      upstream&.close
      client&.close
      server.close unless server.closed?
    end
    thread.report_on_exception = false
    { url: "http://127.0.0.1:#{server.local_address.ip_port}", thread:, server:, errors: }
  end

  def cleanup_proxy(proxy)
    proxy.fetch(:server).close unless proxy.fetch(:server).closed?
    return unless proxy.fetch(:thread).alive?

    proxy.fetch(:thread).kill
    proxy.fetch(:thread).join
  end

  def read_http_message(socket)
    message = +""
    message << socket.readpartial(4096) until message.include?("\r\n\r\n")
    header, body = message.split("\r\n\r\n", 2)
    length = header[/^Content-Length:\s*(\d+)/i, 1].to_i
    body << socket.read(length - body.bytesize) if body.bytesize < length
    "#{header}\r\n\r\n#{body}"
  end

  def available_port
    server = TCPServer.new("127.0.0.1", 0)
    server.local_address.ip_port
  ensure
    server&.close
  end
end
