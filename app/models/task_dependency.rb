class TaskDependency < ApplicationRecord
  belongs_to :task
  belongs_to :blocker, class_name: "Task"

  validates :blocker_id, uniqueness: { scope: :task_id }
  validate :tasks_belong_to_same_plan
  validate :task_does_not_block_itself
  validate :dependency_does_not_create_cycle

  private

  def tasks_belong_to_same_plan
    return if task.nil? || blocker.nil? || task.task_plan == blocker.task_plan

    errors.add(:blocker, "must belong to the same task plan as the task")
  end

  def task_does_not_block_itself
    return unless task && blocker && (task.equal?(blocker) || (task.id && task.id == blocker.id))

    errors.add(:blocker, "cannot be the task itself")
  end

  def dependency_does_not_create_cycle
    return unless task_id && blocker_id

    pending = [ blocker_id ]
    visited = {}

    until pending.empty?
      current_id = pending.pop
      if current_id == task_id
        errors.add(:blocker, "cannot create a dependency cycle")
        return
      end
      next if visited[current_id]

      visited[current_id] = true
      dependencies = TaskDependency.where(task_id: current_id)
      dependencies = dependencies.where.not(id:) if id
      pending.concat(dependencies.pluck(:blocker_id))
    end
  end
end
