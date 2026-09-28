class RecoveryStatus
  def initialize(project)
    @project = project
  end

  def as_json(*)
    {
      project: @project.as_json(only: %i[id name repository_identity remote_url default_branch created_at updated_at]),
      task_plans: unfinished_plans.map { |plan| plan.as_json(only: %i[id project_id key title status version created_at updated_at]) },
      tasks: unfinished_tasks.map { |task| serialize_task(task) }
    }
  end

  private

  def unfinished_plans
    @project.task_plans.joins(:tasks).where.not(tasks: { status: "completed" }).distinct.order(:id)
  end

  def unfinished_tasks
    @project.tasks.includes(:blockers, :workflow).where.not(status: "completed").order(:id)
  end

  def serialize_task(task)
    task.as_json(only: %i[id task_plan_id workflow_id key title status current_step claim_id version pause_kind
      pause_message pause_step answer created_at updated_at]).merge(
        "workflow_key" => task.workflow.key,
        "workflow_revision" => task.workflow.revision,
        "blocker_ids" => task.blocker_ids.sort
      )
  end
end
