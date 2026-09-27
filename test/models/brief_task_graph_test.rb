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

  test "rejects invalid graphs atomically under the publication fence" do
    claim = advance_brief_to_publish
    invalid_definitions = [
      [ @definitions.first.except("title") ],
      [ @definitions.first.merge("blocker_keys" => [ "missing" ]) ],
      [ @definitions.first.merge("blocker_keys" => [ "api" ]) ],
      [ @definitions.first.merge("blocker_keys" => [ "cli" ]), @definitions.last ],
      [ @definitions.first, @definitions.last.merge("blocker_keys" => [ "api" ]),
        { "key" => "api", "title" => "Duplicate", "description_markdown" => "Duplicate", "blocker_keys" => [] } ]
    ]
    invalid_definitions.each do |definitions|
      assert_no_difference [ -> { Task.count }, -> { TaskDependency.count } ] do
        assert_raises(BriefTaskGraph::InvalidDefinition) do
          @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner",
            claim_version: claim.claim_version, children: definitions)
        end
      end
    end

    other = create_task(project: @project)
    assert_raises(BriefTaskGraph::InvalidDefinition) { @graph.observe(parent: other) }
  end

  test "materializes the whole graph with parent and sibling blockers and supports observation recovery" do
    claim = advance_brief_to_publish
    result = nil

    assert_difference -> { Task.count }, 2 do
      assert_difference -> { TaskDependency.count }, 3 do
        result = @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner",
          claim_version: claim.claim_version, children: @definitions)
      end
    end
    assert_match(/\Asha256:[0-9a-f]{64}\z/, result[:digest])

    api = @brief.children.find_by!(title: "Build API")
    cli = @brief.children.find_by!(title: "Build CLI")
    assert_equal @development_type, api.task_type
    assert_equal [ @brief ], api.blockers
    assert_equal [ @brief, api ].sort_by(&:id), cli.blockers.sort_by(&:id)
    lifecycle = TaskLifecycle.new
    assert_nil lifecycle.claim_next!(project: @project, task_type: @development_type, owner_id: "worker")

    observed = @graph.observe(parent: @brief)
    assert_equal result[:digest], observed[:digest]
    assert_equal [ api.id, cli.id ].sort, observed[:children].map { |entry| entry[:task].id }.sort
    cli_entry = observed[:children].find { |entry| entry[:task] == cli }
    assert_equal [ api.id ], cli_entry[:sibling_blocker_ids]

    completed = lifecycle.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
      claim_version: claim.claim_version, step: "publish", outcome: "published", artifact: "# Publish")
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

    assert_match(/before its approved child graph is materialized/, error.message)
    assert_equal before, claim.reload.attributes
    assert_not claim.accepted_artifacts.key?("publish")
  end

  test "rejects non-graph backward publication outcomes after materialization without accepting an artifact" do
    claim = advance_brief_to_publish
    @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      children: @definitions)
    before = claim.reload.attributes

    %w[base_moved review_invalid].each do |outcome|
      error = assert_raises(TaskLifecycle::InvalidTransition) do
        TaskLifecycle.new.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
          claim_version: claim.claim_version, step: "publish", outcome:, artifact: "# Backward")
      end
      assert_match(/cannot return publication to an earlier step/, error.message)
      assert_equal before, claim.reload.attributes
      assert_not claim.accepted_artifacts.key?("publish")
    end
  end

  test "graph_invalid atomically retracts an unstarted graph for correction" do
    claim = advance_brief_to_publish
    @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      children: @definitions)

    assert_difference -> { Task.count }, -2 do
      corrected = TaskLifecycle.new.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
        claim_version: claim.claim_version, step: "publish", outcome: "graph_invalid", artifact: "# Invalid graph")
      assert_equal [ "active", "brief" ], corrected.values_at(:status, :current_step)
    end
    assert_empty @brief.children.reload
    assert_nil @graph.observe(parent: @brief)[:digest]
  end

  test "accepts materialization followed by terminal publication" do
    claim = advance_brief_to_publish
    @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      children: @definitions)

    completed = TaskLifecycle.new.report_attempt!(task_id: @brief.id, owner_id: "brief-owner",
      claim_version: claim.claim_version, step: "publish", outcome: "published", artifact: "# Publish")

    assert_equal [ "completed", "publish", nil ], completed.values_at(:status, :current_step, :owner_id)
  end

  test "requires the exact fence and distinguishes exact retries from conflicts" do
    claim = advance_brief_to_publish

    assert_no_difference -> { Task.count } do
      assert_raises(TaskLifecycle::Conflict) do
        @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner",
          claim_version: claim.claim_version - 1, children: @definitions)
      end
    end

    assert_no_difference -> { Task.count } do
      assert_raises(TaskLifecycle::Conflict) do
        @graph.materialize!(parent_id: @brief.id, owner_id: "wrong-owner", claim_version: claim.claim_version,
          children: @definitions)
      end
    end

    first = @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      children: @definitions)
    assert_no_difference -> { Task.count } do
      retry_result = @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner",
        claim_version: claim.claim_version, children: @definitions)
      assert_equal false, retry_result[:created]
      assert_equal first[:digest], retry_result[:digest]
    end
    assert_no_difference -> { Task.count } do
      assert_raises(TaskLifecycle::Conflict) do
        @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
          children: @definitions.map { |child| child.merge("title" => "Changed #{child.fetch("title")}") })
      end
    end
  end

  test "requires materialization to match the approved graph identity" do
    claim = advance_brief_to_publish

    assert_no_difference [ -> { Task.count }, -> { TaskDependency.count } ] do
      assert_raises(TaskLifecycle::Conflict) do
        @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
          children: [ @definitions.first.merge("title" => "Wrong") ])
      end
    end
    review = @brief.reload.accepted_artifacts.fetch("review")
    assert_equal review.fetch("graph_digest"), @graph.definition(parent: @brief, children: @definitions).fetch("digest")
  end

  test "does not replace an existing graph whose observed identity conflicts with approval" do
    claim = advance_brief_to_publish
    @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      children: @definitions)
    child_ids = @brief.children.order(:id).pluck(:id)
    Task.where(id: child_ids.first).update_all(title: "Unexpected persisted title")
    before = @graph.observe(parent: @brief)

    assert_no_difference [ -> { Task.count }, -> { TaskDependency.count } ] do
      assert_raises(TaskLifecycle::Conflict) do
        @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
          children: @definitions)
      end
    end
    assert_equal child_ids, @brief.children.reload.order(:id).pluck(:id)
    assert_equal before[:digest], @graph.observe(parent: @brief)[:digest]
  end

  test "bounds graph resources before persistence and validates depth iteratively" do
    claim = advance_brief_to_publish
    invalid = [
      Array.new(BriefTaskGraph::MAX_CHILDREN + 1) { |index| child_definition("c#{index}") },
      [ child_definition("k" * (BriefTaskGraph::MAX_KEY_BYTES + 1)) ],
      [ child_definition("child", title: "t" * (BriefTaskGraph::MAX_TITLE_BYTES + 1)) ],
      [ child_definition("child", description: "d" * (BriefTaskGraph::MAX_DESCRIPTION_BYTES + 1)) ],
      Array.new(BriefTaskGraph::MAX_DEPTH + 1) do |index|
        child_definition("depth#{index}", blockers: index.zero? ? [] : [ "depth#{index - 1}" ])
      end,
      Array.new(24) do |index|
        child_definition("dense#{index}", blockers: Array.new(index) { |blocker| "dense#{blocker}" })
      end,
      Array.new(BriefTaskGraph::MAX_CHILDREN) do |index|
        child_definition("large#{index}", description: "d" * BriefTaskGraph::MAX_DESCRIPTION_BYTES)
      end
    ]

    invalid.each do |children|
      assert_no_difference [ -> { Task.count }, -> { TaskDependency.count } ] do
        assert_raises(BriefTaskGraph::InvalidDefinition) do
          @graph.definition(parent: @brief, children:)
        end
      end
    end
    assert_equal claim.claim_version, @brief.reload.claim_version
  end

  test "rejects an oversized blocker list before acquiring the SQLite writer lock" do
    claim = advance_brief_to_publish
    lock_attempted = false
    graph_class = Class.new(BriefTaskGraph) do
      define_method(:initialize) { |callback| @callback = callback }

      private

      define_method(:lock_parent!) do |parent_id|
        @callback.call
        super(parent_id)
      end
    end
    children = [ child_definition("child", blockers: Array.new(BriefTaskGraph::MAX_EDGES + 1) { |index| "b#{index}" }) ]

    assert_raises(BriefTaskGraph::InvalidDefinition) do
      graph_class.new(-> { lock_attempted = true }).materialize!(parent_id: @brief.id, owner_id: "brief-owner",
        claim_version: claim.claim_version, children:)
    end
    assert_equal false, lock_attempted
  end

  test "cancelling a materialized brief cancels every child atomically" do
    claim = advance_brief_to_publish
    @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      children: @definitions)

    cancelled = TaskLifecycle.new.cancel!(task_id: @brief.id)

    assert_equal "cancelled", cancelled.status
    assert_equal [ "cancelled" ], @brief.children.reload.pluck(:status).uniq
    assert_nil TaskLifecycle.new.claim_next!(project: @project, task_type: @development_type, owner_id: "worker")
  end

  test "rolls back every child when persistence fails partway through materialization" do
    claim = advance_brief_to_publish
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
            claim_version: claim.claim_version, children: @definitions)
        end
      end
    end
  end

  test "requires the publication step and an unexpired lease" do
    lifecycle = TaskLifecycle.new
    claim = lifecycle.claim!(task_id: @brief.id, owner_id: "brief-owner")
    assert_raises(TaskLifecycle::Conflict) do
      @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
        children: @definitions)
    end

    claim = lifecycle.report_attempt!(task_id: claim.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      step: "brief", outcome: "specified", artifact: "# Brief")
    claim = lifecycle.report_attempt!(task_id: claim.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      step: "review", outcome: "approved", artifact: "# Review", brief_graph: { "children" => @definitions })
    Task.where(id: claim.id).update_all(lease_expires_at: 1.minute.ago)
    assert_raises(TaskLifecycle::Conflict) do
      @graph.materialize!(parent_id: @brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
        children: @definitions)
    end
  end

  private

  def advance_brief_to_publish
    lifecycle = TaskLifecycle.new
    task = lifecycle.claim!(task_id: @brief.id, owner_id: "brief-owner")
    task = lifecycle.report_attempt!(task_id: task.id, owner_id: "brief-owner", claim_version: task.claim_version,
      step: "brief", outcome: "specified", artifact: "# Brief")
    lifecycle.report_attempt!(task_id: task.id, owner_id: "brief-owner", claim_version: task.claim_version,
      step: "review", outcome: "approved", artifact: "# Review", brief_graph: { "children" => @definitions })
  end


  def child_definition(key, title: "Child", description: "Work", blockers: [])
    { "key" => key, "title" => title, "description_markdown" => description, "blocker_keys" => blockers }
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
    children = [ { "key" => "child", "title" => "Child", "description_markdown" => "Work",
      "blocker_keys" => [] } ]
    claim = lifecycle.report_attempt!(task_id: brief.id, owner_id: "brief-owner", claim_version: claim.claim_version,
      step: "review", outcome: "approved", artifact: "# Review", brief_graph: { "children" => children })
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
    arguments = { parent_id: brief.id, owner_id: "brief-owner", claim_version: claim.claim_version, children: }

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

    assert_equal 2, outcomes.grep(Hash).size
    assert_equal [ false, true ], outcomes.map { |outcome| outcome.fetch(:created) }.sort_by(&:to_s)
    assert_equal 1, brief.children.count
    assert_equal outcomes.grep(Hash).first.fetch(:digest), BriefTaskGraph.new.observe(parent: brief)[:digest]
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

  test "materialization serializes with cancellation without stranding children" do
    test_case = concurrent_brief
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

    materialize_thread = run_concurrently(test_case[:results]) do
      coordinated_graph.new.materialize!(**test_case[:materialize])
    end
    Timeout.timeout(5) { graph_locked.pop }
    cancel_thread = run_concurrently(test_case[:results]) do
      TaskLifecycle.new.cancel!(task_id: test_case.fetch(:brief).id)
    end
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { test_case[:results].pop } }
    release_graph << true
    [ materialize_thread, cancel_thread ].each(&:join)
    outcomes = 2.times.map { test_case[:results].pop }

    assert_equal 1, outcomes.count { |outcome| outcome.is_a?(Hash) }
    assert_equal 1, outcomes.count { |outcome| outcome.is_a?(Task) && outcome.status == "cancelled" }
    assert_equal "cancelled", test_case.fetch(:brief).reload.status
    assert_equal [ "cancelled" ], test_case.fetch(:brief).children.pluck(:status).uniq
  end

  test "materialization serializes with graph correction without partial children" do
    test_case = concurrent_brief
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

    materialize_thread = run_concurrently(test_case[:results]) do
      coordinated_graph.new.materialize!(**test_case[:materialize])
    end
    Timeout.timeout(5) { graph_locked.pop }
    correction_thread = run_concurrently(test_case[:results]) do
      TaskLifecycle.new.report_attempt!(**test_case[:report].merge(outcome: "graph_invalid"))
    end
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { test_case[:results].pop } }
    release_graph << true
    [ materialize_thread, correction_thread ].each(&:join)
    outcomes = 2.times.map { test_case[:results].pop }

    assert_equal 1, outcomes.count { |outcome| outcome.is_a?(Hash) }
    corrected = outcomes.find { |outcome| outcome.is_a?(Task) }
    assert_equal [ "active", "brief", 4 ], corrected.values_at(:status, :current_step, :claim_version)
    assert_equal "graph_invalid", corrected.accepted_artifacts.dig("publish", "outcome")
    assert_empty test_case.fetch(:brief).children.reload
    assert_nil BriefTaskGraph.new.observe(parent: test_case.fetch(:brief))[:digest]
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
    children = [ { "key" => "child", "title" => "Child", "description_markdown" => "Work",
      "blocker_keys" => [] } ]
    claim = lifecycle.report_attempt!(task_id: brief.id, owner_id:,
      claim_version: claim.claim_version, step: "review", outcome: "approved", artifact: "# Review",
      brief_graph: { "children" => children })
    {
      brief:, results: Queue.new,
      materialize: { parent_id: brief.id, owner_id:, claim_version: claim.claim_version, children: },
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
    assert_match(/\Asha256:[0-9a-f]{64}\z/, BriefTaskGraph.new.observe(parent: brief)[:digest])
  end
end
