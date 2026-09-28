class ProjectsController < ApplicationController
  def create
    remote_url = required_string(:remote_url, max_bytes: CoordinationLimits::MAX_URL_BYTES)
    project = Project.create!(
      name: required_string(:name, max_bytes: CoordinationLimits::MAX_NAME_BYTES),
      remote_url:,
      default_branch: required_string(:default_branch, max_bytes: CoordinationLimits::MAX_NAME_BYTES),
      repository_identity: params[:repository_identity].present? ?
        required_string(:repository_identity, max_bytes: CoordinationLimits::MAX_URL_BYTES) : RepositoryIdentity.normalize(remote_url)
    )

    render_project(project, :created)
  end

  def index
    identity = required_string(:repository_identity, max_bytes: CoordinationLimits::MAX_URL_BYTES)
    project = Project.find_by(repository_identity: identity)
    unless project
      return render json: {
        error: "not_found",
        message: "Project is not registered under #{identity.inspect}; register it with `kos project create` first."
      }, status: :not_found
    end
    render_project(project)
  end

  def show
    render_project(Project.find(params[:id]))
  end

  def update
    project = Project.find(params[:id])
    attributes = %i[name remote_url default_branch repository_identity].filter_map do |name|
      max_bytes = %i[remote_url repository_identity].include?(name) ? CoordinationLimits::MAX_URL_BYTES :
        CoordinationLimits::MAX_NAME_BYTES
      [ name, required_string(name, max_bytes:) ] if params.key?(name)
    end.compact
    attributes = attributes.to_h
    raise ActionController::BadRequest, "no editable project fields were provided" if attributes.empty?

    project.update!(attributes)
    render_project(project)
  end

  private

  def render_project(project, status = :ok)
    render json: { project: project.as_json(only: %i[id name repository_identity remote_url default_branch created_at updated_at]) },
      status:
  end
end
