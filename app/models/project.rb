class Project < ApplicationRecord
  has_many :task_plans, dependent: :restrict_with_error
  has_many :tasks, through: :task_plans

  validates :name, :remote_url, :default_branch, :repository_identity, presence: true
  validates :repository_identity, uniqueness: true
  validate :repository_identity_matches_remote
  validate :default_branch_is_valid

  private

  def repository_identity_matches_remote
    normalized = RepositoryIdentity.normalize(remote_url)
    errors.add(:repository_identity, "must match remote URL") unless repository_identity == normalized
  rescue RepositoryIdentity::Invalid => error
    errors.add(:remote_url, error.message)
  end

  def default_branch_is_valid
    return if default_branch.blank?

    errors.add(:default_branch, "must be a valid Git branch name") unless GitBranch.valid?(default_branch)
  end
end
