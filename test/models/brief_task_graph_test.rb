require "test_helper"
require "timeout"

class BriefTaskGraphTest < ActiveSupport::TestCase
  setup do
    BuiltInCatalog.install!
    @project = create_project
    @brief_type = TaskType.find_by!(key: "brief")
    @development_type = TaskType.find_by!(key: "development")
    @brief = TaskLifecycle.new.create!(project: @project, task_type: @brief_type, title: "Specify feature",
      description_markdown: "Request")
    @graph = BriefTaskGraph.new
    @definitions = [
      { "key" => "api", "title" => "Build API", "description_markdown" => "API work", "blocker_keys" => [] },
      { "key" => "cli", "title" => "Build CLI", "description_markdown" => "CLI work", "blocker_keys" => [ "api" ] }
    ]
  end

  test "validates a canonical graph and rejects incomplete cyclic and foreign definitions" do
    first = @graph.validate!(parent: @brief, children: @definitions)
    reordered = @graph.validate!(parent: @brief, children: @definitions.reverse)
    assert_equal first[:digest], reordered[:digest]
    assert_match(/\Asha256:[0-9a-f]{64}\z/, first[:digest])

    invalid_definitions = [
      [ @definitions.first.except("title") ],
      [ @definitions.first.merge("blocker_keys" => [ "missing" ]) ],
      [ @definitions.first.merge("blocker_keys" => [ "api" ]) ],
      [ @definitions.first.merge("blocker_keys" => [ "cli" ]), @definitions.last ],
      [ @definitions.first, @definitions.last.merge("blocker_keys" => [ "api" ]),
        { "key" => "api", "title" => "Duplicate", "description_markdown" => "Duplicate", "blocker_keys" => [] } ]
    ]
    invalid_definitions.each do |definitions|
      assert_raises(BriefTaskGraph::InvalidDefinition) { @graph.validate!(parent: @brief, children: definitions) }
    end

    other = create_task(project: @project)
    assert_raises(BriefTaskGraph::InvalidDefinition) { @graph.validate!(parent: other, children: @definitions) }
    assert_raises(BriefTaskGraph::InvalidDefinition) { @graph.observe(parent: other) }
  end

  test "materializes the whole graph with parent and sibling blockers and supports observation recovery" do
    claim = advance_brief_to_publish
    validation = @graph.validate!(parent: @brief, children: @definitions)

    assert_difference -> { Task.count }, 2 do
      assert_difference -> { TaskDependency.count }, 3 do
        result = @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner",
          claim_version: claim.claim_version, expected_digest: validation[:digest], children: @definitions)
        assert_equal validation[:digest], result[:digest]
      end
    end

    api = @brief.children.find_by!(title: "Build API")
    cli = @brief.children.find_by!(title: "Build CLI")
    assert_equal @development_type, api.task_type
    assert_equal [ @brief ], api.blockers
    assert_equal [ @brief, api ].sort_by(&:id), cli.blockers.sort_by(&:id)
    lifecycle = TaskLifecycle.new
    assert_nil lifecycle.claim_next!(project: @project, task_type: @development_type, owner_id: "worker")

    observed = @graph.observe(parent: @brief)
    assert_equal validation[:digest], observed[:digest]
    assert_equal [ api.id, cli.id ].sort, observed[:children].map { |entry| entry[:task].id }.sort
    cli_entry = observed[:children].find { |entry| entry[:task] == cli }
    assert_equal [ api.id ], cli_entry[:sibling_blocker_ids]

    verification = lifecycle.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
      claim_version: claim.claim_version, step: "publish", outcome: "published", artifact: "# Publish")
    completed = lifecycle.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
      claim_version: verification.claim_version, step: "verify", outcome: "verified", artifact: "# Verify")
    assert_equal "completed", completed.status
    assert_equal api, lifecycle.claim_next!(project: @project, task_type: @development_type, owner_id: "worker")
  end

  test "rejects published before materialization without accepting an artifact" do
    claim = advance_brief_to_publish
    before = claim.attributes

    error = assert_raises(TaskLifecycle::InvalidTransition) do
      TaskLifecycle.new.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
        claim_version: claim.claim_version, step: "publish", outcome: "published", artifact: "# Publish")
    end

    assert_match(/before its child graph is materialized/, error.message)
    assert_equal before, claim.reload.attributes
    assert_not claim.accepted_artifacts.key?("publish")
  end

  test "rejects backward publication outcomes after materialization without accepting an artifact" do
    claim = advance_brief_to_publish
    validation = @graph.validate!(parent: @brief, children: @definitions)
    @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      expected_digest: validation[:digest], children: @definitions)
    before = claim.reload.attributes

    %w[base_moved graph_invalid review_invalid].each do |outcome|
      error = assert_raises(TaskLifecycle::InvalidTransition) do
        TaskLifecycle.new.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
          claim_version: claim.claim_version, step: "publish", outcome:, artifact: "# Backward")
      end
      assert_match(/cannot return publication to an earlier step/, error.message)
      assert_equal before, claim.reload.attributes
      assert_not claim.accepted_artifacts.key?("publish")
    end
  end

  test "accepts materialization followed by published and verification" do
    claim = advance_brief_to_publish
    validation = @graph.validate!(parent: @brief, children: @definitions)
    @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      expected_digest: validation[:digest], children: @definitions)

    published = TaskLifecycle.new.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
      claim_version: claim.claim_version, step: "publish", outcome: "published", artifact: "# Publish")
    verified = TaskLifecycle.new.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
      claim_version: published.claim_version, step: "verify", outcome: "verified", artifact: "# Verify")

    assert_equal [ "active", "verify" ], published.values_at(:status, :current_step)
    assert_equal "completed", verified.status
  end

  test "digest claim and repeated materialization conflicts roll back without partial children" do
    claim = advance_brief_to_publish
    digest = @graph.validate!(parent: @brief, children: @definitions)[:digest]

    assert_no_difference -> { Task.count } do
      assert_raises(TaskLifecycle::Conflict) do
        @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner",
          claim_version: claim.claim_version - 1, expected_digest: digest, children: @definitions)
      end
    end

    assert_no_difference -> { Task.count } do
      assert_raises(TaskLifecycle::Conflict) do
        @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
          expected_digest: "sha256:wrong", children: @definitions)
      end
    end

    @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      expected_digest: digest, children: @definitions)
    assert_no_difference -> { Task.count } do
      assert_raises(TaskLifecycle::Conflict) do
        @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
          expected_digest: digest, children: @definitions)
      end
    end
    assert_raises(TaskLifecycle::Conflict) { @graph.validate!(parent: @brief, children: @definitions) }
  end

  test "rolls back every child when persistence fails partway through materialization" do
    claim = advance_brief_to_publish
    digest = @graph.validate!(parent: @brief, children: @definitions)[:digest]
    failing_graph_class = Class.new(BriefTaskGraph) do
      private

      def create_dependency!(task:, blocker:)
        @dependency_count = @dependency_count.to_i + 1
        raise "simulated persistence failure" if @dependency_count == 2

        super
      end
    end

    assert_no_difference -> { Task.count } do
      assert_no_difference -> { TaskDependency.count } do
        assert_raises(RuntimeError) do
          failing_graph_class.new.materialize!(parent_id: @brief.id, owner_id: "brief-owner",
            claim_version: claim.claim_version, expected_digest: digest, children: @definitions)
        end
      end
    end
  end

  test "requires the publication step and an unexpired lease" do
    lifecycle = TaskLifecycle.new
    claim = lifecycle.claim!(task_id: @brief.id, owner_id: "brief-owner")
    digest = @graph.validate!(parent: @brief, children: @definitions)[:digest]
    assert_raises(TaskLifecycle::Conflict) do
      @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
        expected_digest: digest, children: @definitions)
    end

    claim = lifecycle.report_attempt!(task_id: claim.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      step: "brief", outcome: "specified", artifact: "# Brief")
    claim = lifecycle.report_attempt!(task_id: claim.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      step: "review", outcome: "approved", artifact: "# Review")
    Task.where(id: claim.id).update_all(lease_expires_at: 1.minute.ago)
    assert_raises(TaskLifecycle::Conflict) do
      @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
        expected_digest: digest, children: @definitions)
    end
  end

  private

  def advance_brief_to_publish
    lifecycle = TaskLifecycle.new
    task = lifecycle.claim!(task_id: @brief.id, owner_id: "brief-owner")
    task = lifecycle.report_attempt!(task_id: task.id, owner_id: "brief-owner", claim_version: task.claim_version,
      step: "brief", outcome: "specified", artifact: "# Brief")
    lifecycle.report_attempt!(task_id: task.id, owner_id: "brief-owner", claim_version: task.claim_version,
      step: "review", outcome: "approved", artifact: "# Review")
  end
end

class BriefTaskGraphConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    TaskDependency.delete_all
    Task.delete_all
    TaskType.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  teardown do
    TaskDependency.delete_all
    Task.delete_all
    TaskType.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  test "overlapping materialization creates one graph and recovers by observation" do
    BuiltInCatalog.install!
    project = create_project
    lifecycle = TaskLifecycle.new
    brief = lifecycle.create!(project:, task_type: TaskType.find_by!(key: "brief"), title: "Brief",
      description_markdown: "Request")
    claim = lifecycle.claim!(task_id: brief.id, owner_id: "brief-owner")
    claim = lifecycle.report_attempt!(task_id: brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      step: "brief", outcome: "specified", artifact: "# Brief")
    claim = lifecycle.report_attempt!(task_id: brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      step: "review", outcome: "approved", artifact: "# Review")
    children = [ { "key" => "child", "title" => "Child", "description_markdown" => "Work",
      "blocker_keys" => [] } ]
    digest = BriefTaskGraph.new.validate!(parent: brief, children:)[:digest]
    locked = Queue.new
    release = Queue.new
    results = Queue.new
    coordinated_graph = Class.new(BriefTaskGraph) do
      define_method(:initialize) do
        @locked = locked
        @release = release
      end

      private

      define_method(:lock_parent!) do |parent_id|
        parent = super(parent_id)
        @locked << true
        @release.pop
        parent
      end
    end
    arguments = { parent_id: brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      expected_digest: digest, children: }

    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << coordinated_graph.new.materialize!(**arguments)
      rescue StandardError => error
        results << error
      end
    end
    Timeout.timeout(5) { locked.pop }
    second = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << BriefTaskGraph.new.materialize!(**arguments)
      rescue StandardError => error
        results << error
      end
    end
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { results.pop } }
    release << true
    first.join
    second.join
    outcomes = 2.times.map { results.pop }

    assert_equal 1, outcomes.grep(Hash).size
    assert_equal 1, outcomes.grep(TaskLifecycle::Conflict).size
    assert_equal 1, brief.children.count
    assert_equal digest, BriefTaskGraph.new.observe(parent: brief)[:digest]
  end

  test "materialization serializes with published and backward reports in both lock orders" do
    published_case = concurrent_brief
    report_locked = Queue.new
    release_report = Queue.new
    reporting_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @report_locked = report_locked
        @release_report = release_report
      end

      private

      define_method(:lock_brief_publication_fence!) do |task, **arguments|
        super(task, **arguments)
        @report_locked << true
        @release_report.pop
      end
    end

    report_thread = run_concurrently(published_case[:results]) do
      reporting_lifecycle.new.report_attempt!(**published_case[:report].merge(outcome: "published"))
    end
    Timeout.timeout(5) { report_locked.pop }
    materialize_thread = run_concurrently(published_case[:results]) do
      BriefTaskGraph.new.materialize!(**published_case[:materialize])
    end
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { published_case[:results].pop } }
    release_report << true
    [ report_thread, materialize_thread ].each(&:join)
    published_outcomes = 2.times.map { published_case[:results].pop }

    assert_equal 1, published_outcomes.grep(Hash).size
    assert_equal 1, published_outcomes.grep(TaskLifecycle::InvalidTransition).size
    assert_safe_unreported_graph(published_case)

    backward_case = concurrent_brief
    graph_locked = Queue.new
    release_graph = Queue.new
    coordinated_graph = Class.new(BriefTaskGraph) do
      define_method(:initialize) do
        @graph_locked = graph_locked
        @release_graph = release_graph
      end

      private

      define_method(:lock_parent!) do |parent_id|
        parent = super(parent_id)
        @graph_locked << true
        @release_graph.pop
        parent
      end
    end

    materialize_thread = run_concurrently(backward_case[:results]) do
      coordinated_graph.new.materialize!(**backward_case[:materialize])
    end
    Timeout.timeout(5) { graph_locked.pop }
    report_thread = run_concurrently(backward_case[:results]) do
      TaskLifecycle.new.report_attempt!(**backward_case[:report].merge(outcome: "base_moved"))
    end
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { backward_case[:results].pop } }
    release_graph << true
    [ materialize_thread, report_thread ].each(&:join)
    backward_outcomes = 2.times.map { backward_case[:results].pop }

    assert_equal 1, backward_outcomes.grep(Hash).size
    assert_equal 1, backward_outcomes.grep(TaskLifecycle::InvalidTransition).size
    assert_safe_unreported_graph(backward_case)
  end

  private

  def concurrent_brief
    BuiltInCatalog.install!
    project = create_project
    lifecycle = TaskLifecycle.new
    brief = lifecycle.create!(project:, task_type: TaskType.find_by!(key: "brief"), title: "Concurrent brief",
      description_markdown: "Request")
    owner_id = "brief-owner-#{brief.id}"
    claim = lifecycle.claim!(task_id: brief.id, owner_id:)
    claim = lifecycle.report_attempt!(task_id: brief.id, owner_id:,
      claim_version: claim.claim_version, step: "brief", outcome: "specified", artifact: "# Brief")
    claim = lifecycle.report_attempt!(task_id: brief.id, owner_id:,
      claim_version: claim.claim_version, step: "review", outcome: "approved", artifact: "# Review")
    children = [ { "key" => "child", "title" => "Child", "description_markdown" => "Work",
      "blocker_keys" => [] } ]
    digest = BriefTaskGraph.new.validate!(parent: brief, children:)[:digest]
    {
      brief:, digest:, results: Queue.new,
      materialize: { parent_id: brief.id, owner_id:, claim_version: claim.claim_version,
        expected_digest: digest, children: },
      report: { task_id: brief.id, owner_id:, claim_version: claim.claim_version,
        step: "publish", artifact: "# Publish" }
    }
  end

  def run_concurrently(results, &operation)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << operation.call
      rescue StandardError => error
        results << error
      end
    end
  end

  def assert_safe_unreported_graph(test_case)
    brief = test_case.fetch(:brief).reload
    assert_equal [ "active", "publish", 3 ], brief.values_at(:status, :current_step, :claim_version)
    assert_not brief.accepted_artifacts.key?("publish")
    assert_equal 1, brief.children.count
    assert_equal 1, TaskDependency.where(task_id: brief.child_ids, blocker_id: brief.id).count
    assert_equal test_case.fetch(:digest), BriefTaskGraph.new.observe(parent: brief)[:digest]
  end
end
