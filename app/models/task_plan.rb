class TaskPlan < ApplicationRecord
  STATUSES = %w[active abandoned].freeze

  belongs_to :project
  has_many :tasks, dependent: :destroy

  validates :key, :title, presence: true
  validates :key, format: { with: /\A[a-z][a-z0-9_-]*\z/ }, uniqueness: { scope: :project_id }
  validates :status, inclusion: { in: STATUSES }
  validates :version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
