class TaskPlan < ApplicationRecord
  belongs_to :project
  has_many :tasks, dependent: :destroy

  validates :key, :title, presence: true
  validates :key, format: { with: /\A[a-z][a-z0-9_-]*\z/ }, uniqueness: { scope: :project_id }
end
