class Task < ApplicationRecord
  belongs_to :project
  belongs_to :task_type
  belongs_to :workflow
  belongs_to :parent, class_name: "Task", optional: true, inverse_of: :children

  has_many :children, class_name: "Task", foreign_key: :parent_id, inverse_of: :parent
  has_many :task_dependencies
  has_many :blockers, through: :task_dependencies
  has_many :blocking_task_dependencies, class_name: "TaskDependency", foreign_key: :blocker_id
  has_many :blocked_tasks, through: :blocking_task_dependencies, source: :task

  validate :current_step_belongs_to_workflow
  validate :parent_belongs_to_project
  validate :parent_does_not_create_cycle
  validate :project_is_immutable, on: :update
  validate :workflow_is_immutable, on: :update
  validate :title_is_immutable, on: :update
  validate :task_type_is_immutable, on: :update
  validate :creation_key_is_immutable, on: :update
  validate :description_is_immutable_after_claim, on: :update
  validate :parent_is_immutable_after_claim, on: :update
  validate :lifecycle_state_changes_through_lifecycle, on: :update

  before_destroy :prevent_destroy

  private

  def current_step_belongs_to_workflow
    return if workflow.nil? || workflow.step_ids.include?(current_step)

    errors.add(:current_step, "must identify a step in the task workflow")
  end

  def parent_belongs_to_project
    return if parent.nil? || project == parent.project

    errors.add(:parent, "must belong to the same project")
  end

  def parent_does_not_create_cycle
    ancestor = parent
    visited = {}

    while ancestor
      if ancestor.equal?(self) || (id && ancestor.id == id)
        errors.add(:parent, "cannot create a cycle")
        return
      end

      key = ancestor.id || ancestor.object_id
      if visited[key]
        errors.add(:parent, "cannot belong to a cyclic hierarchy")
        return
      end

      visited[key] = true
      ancestor = ancestor.parent
    end
  end

  def project_is_immutable
    errors.add(:project, "cannot change after task creation") if will_save_change_to_project_id?
  end

  def workflow_is_immutable
    errors.add(:workflow, "cannot change after task creation") if will_save_change_to_workflow_id?
  end

  def description_is_immutable_after_claim
    return unless will_save_change_to_description_markdown?
    return if pending_and_unclaimed_in_database?

    errors.add(:description_markdown, "can change only while the task is pending and unclaimed")
  end

  def parent_is_immutable_after_claim
    return unless will_save_change_to_parent_id?
    return if pending_and_unclaimed_in_database?

    errors.add(:parent, "can change only while the task is pending and unclaimed")
  end

  def task_type_is_immutable
    errors.add(:task_type, "cannot change after task creation") if will_save_change_to_task_type_id?
  end

  def creation_key_is_immutable
    errors.add(:creation_key, "cannot change after task creation") if will_save_change_to_creation_key?
  end

  def title_is_immutable
    errors.add(:title, "cannot change after task creation") if will_save_change_to_title?
  end

  def lifecycle_state_changes_through_lifecycle
    lifecycle_fields = %w[
      status current_step owner_id claim_version lease_expires_at accepted_artifacts pause_message pause_step
      pause_claim_version human_answer human_answer_step human_answer_claim_version
    ]
    return unless lifecycle_fields.any? { |field| will_save_change_to_attribute?(field) }

    errors.add(:base, "lifecycle state can change only through TaskLifecycle")
  end

  def pending_and_unclaimed_in_database?
    self.class.where(id:).where(status: "pending", claim_version: 0).exists?
  end

  def prevent_destroy
    errors.add(:base, "tasks cannot be deleted; cancel the task instead")
    throw :abort
  end
end
