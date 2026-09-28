class Task < ApplicationRecord
  STATUSES = %w[pending active needs_human blocked completed abandoned].freeze

  belongs_to :task_plan
  belongs_to :workflow
  has_one :project, through: :task_plan

  has_many :task_dependencies, dependent: :destroy
  has_many :blockers, through: :task_dependencies
  has_many :blocking_task_dependencies, class_name: "TaskDependency", foreign_key: :blocker_id,
    dependent: :destroy
  has_many :blocked_tasks, through: :blocking_task_dependencies, source: :task

  validates :key, :title, :description_markdown, :current_step, presence: true
  validates :key, uniqueness: { scope: :task_plan_id }
  validates :status, inclusion: { in: STATUSES }
  validates :version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :current_step_belongs_to_workflow

  private

  def current_step_belongs_to_workflow
    return if workflow&.step_ids&.include?(current_step)

    errors.add(:current_step, "must identify a step in the task workflow")
  end
end
