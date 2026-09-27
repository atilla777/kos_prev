class LifecycleSchedulerCli
  attr_reader :operations, :requests

  def initialize(project:, lifecycle:, session_ids:)
    @project = project
    @lifecycle = lifecycle
    @session_ids = session_ids.dup
    @operations = []
    @requests = []
  end

  def session_id
    operations << [ :session_id ]
    @session_ids.shift || raise("no scheduler session ID")
  end

  def resumable(project_id:, task_type_key:)
    task_type = selection(project_id, task_type_key)
    operations << [ :resumable, project_id, task_type_key ]
    @lifecycle.resumable(project: @project, task_type:).map { |task| envelope(task) }
  end

  def claim_next(project_id:, task_type_key:, owner_id:)
    task_type = selection(project_id, task_type_key)
    operations << [ :claim_next, project_id, task_type_key, owner_id ]
    task = @lifecycle.claim_next!(project: @project, task_type:, owner_id:)
    envelope(task) if task
  end

  def create_or_get(project_id:, kind:, request:, owner_id:)
    selection(project_id, kind)
    operations << [ :create_or_get, project_id, kind, owner_id ]
    requests << request
    envelope(@lifecycle.create_or_get_request!(project: @project, kind:, request:, owner_id:))
  end

  def show(task_id)
    operations << [ :show, task_id ]
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
    operations << [ :resume, arguments ]
    @lifecycle.resume!(**arguments)
  end

  private

  def selection(project_id, task_type_key)
    raise "wrong project" unless project_id == @project.id

    TaskType.find_by!(key: task_type_key)
  end

  def envelope(task)
    { "task" => task.slice(:id, :status, :current_step, :claim_version).stringify_keys }
  end
end
