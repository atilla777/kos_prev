class ProjectsController < ApplicationController
  def create
    remote_url = required_string(:remote_url)
    project = Project.create!(
      name: required_string(:name),
      remote_url:,
      default_branch: required_string(:default_branch),
      repository_identity: params[:repository_identity].presence || RepositoryIdentity.normalize(remote_url)
    )

    render_project(project, :created)
  end

  def index
    project = Project.find_by!(repository_identity: required_string(:repository_identity))
    render_project(project)
  end

  def show
    render_project(Project.find(params[:id]))
  end

  def update
    project = Project.find(params[:id])
    attributes = %i[name remote_url default_branch repository_identity].filter_map do |name|
      [ name, required_string(name) ] if params.key?(name)
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
