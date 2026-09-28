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
  validates :key, :current_step, :pause_step, bounded_text: { maximum: CoordinationLimits::MAX_KEY_BYTES }
  validates :title, bounded_text: { maximum: CoordinationLimits::MAX_NAME_BYTES }
  validates :description_markdown, :pause_message, :answer,
    bounded_text: { maximum: CoordinationLimits::MAX_TEXT_BYTES }
  validates :claim_id, bounded_text: { maximum: CoordinationLimits::MAX_CLAIM_ID_BYTES }
  validates :key, uniqueness: { scope: :task_plan_id }
  validates :status, inclusion: { in: STATUSES }
  validates :version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :current_step_belongs_to_workflow
  validate :accepted_results_within_limit

  private

  def current_step_belongs_to_workflow
    return if workflow&.step_ids&.include?(current_step)

    errors.add(:current_step, "must identify a step in the task workflow")
  end

  def accepted_results_within_limit
    valid_results = accepted_results.values.all? do |entry|
      result = entry["result"] if entry.is_a?(Hash)
      result.nil? || CoordinationLimits.valid_text?(result, max_bytes: CoordinationLimits::MAX_RESULT_BYTES,
        allow_blank: true)
    end
    errors.add(:accepted_results, "must contain results of at most 1 MiB each") unless valid_results
    return if JSON.generate(accepted_results).bytesize <= CoordinationLimits::MAX_ACCEPTED_RESULTS_BYTES

    errors.add(:accepted_results, "must total at most 4 MiB")
  end
end
