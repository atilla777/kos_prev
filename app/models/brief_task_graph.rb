require "digest"
require "set"

class BriefTaskGraph
  class InvalidDefinition < StandardError; end

  REQUIRED_CHILD_KEYS = %w[key title description_markdown blocker_keys].freeze
  MAX_CHILDREN = 64
  MAX_EDGES = 256
  MAX_DEPTH = 32
  MAX_KEY_BYTES = 100
  MAX_TITLE_BYTES = 200
  MAX_DESCRIPTION_BYTES = 16.kilobytes
  MAX_DEFINITION_BYTES = 1.megabyte

  def definition(parent:, children:)
    normalized = normalize!(parent:, children:)
    { "children" => normalized, "digest" => definition_digest(normalized) }
  end

  def materialize!(parent_id:, owner_id:, claim_version:, children:)
    submitted = definition(parent: Task.includes(:task_type).find(parent_id), children:)
    Task.transaction do
      parent = lock_parent!(parent_id)
      validate_claim!(parent, owner_id:, claim_version:)
      approved = approved_definition!(parent)
      unless submitted.fetch("digest") == approved.fetch("digest")
        raise TaskLifecycle::Conflict, "child graph does not match the approved graph identity"
      end

      observed = observe(parent:)
      if observed.fetch(:digest) == submitted.fetch("digest")
        return { digest: observed.fetch(:digest), children: observed.fetch(:children).map { |entry| entry.fetch(:task) },
                 created: false }
      end
      if observed.fetch(:digest)
        raise TaskLifecycle::Conflict, "materialized child graph conflicts with the approved graph identity"
      end

      normalized = submitted.fetch("children")

      task_type = TaskType.find_by!(key: "development")
      created = normalized.to_h do |definition|
        task = Task.create!(project: parent.project, task_type:, workflow: task_type.workflow, parent:,
          title: definition.fetch("title"), description_markdown: definition.fetch("description_markdown"),
          current_step: task_type.workflow.first_step_id)
        [ definition.fetch("key"), task ]
      end

      normalized.each do |definition|
        task = created.fetch(definition.fetch("key"))
        ([ parent ] + definition.fetch("blocker_keys").map { |key| created.fetch(key) }).each do |blocker|
          create_dependency!(task:, blocker:)
        end
      end

      { digest: submitted.fetch("digest"), children: created.values, created: true }
    end
  end

  def retract_locked!(parent:)
    children = parent.children.to_a
    return if children.empty?

    child_ids = children.map(&:id)
    safe = children.all? { |child| child.status == "pending" && child.claim_version.zero? } &&
      Task.where(parent_id: child_ids).none? &&
      TaskDependency.where(blocker_id: child_ids).where.not(task_id: child_ids).none?
    raise TaskLifecycle::Conflict, "materialized child graph is no longer safe to replace" unless safe

    TaskDependency.where(task_id: child_ids).or(TaskDependency.where(blocker_id: child_ids)).delete_all
    Task.where(id: child_ids).delete_all
  end

  def cancel_children_locked!(parent:, now:)
    parent.children.where.not(status: %w[completed cancelled]).update_all(
      status: "cancelled",
      owner_id: nil,
      lease_expires_at: nil,
      pause_message: nil,
      pause_step: nil,
      pause_claim_version: nil,
      human_answer: nil,
      human_answer_step: nil,
      human_answer_claim_version: nil,
      claim_version: Arel.sql("claim_version + CASE WHEN status = 'active' THEN 1 ELSE 0 END"),
      updated_at: now
    )
  end

  def observe(parent:)
    raise InvalidDefinition, "task must be a built-in brief" unless parent.task_type.key == "brief"

    children = parent.children.includes(:task_type, :blockers).order(:id).to_a
    child_ids = children.map(&:id).to_set
    positions = children.each_with_index.to_h { |child, index| [ child.id, index ] }
    accepted_artifacts = Task.where(id: parent.id).pick(:accepted_artifacts) || {}
    approved_keys = accepted_artifacts.dig("review", "brief_graph", "children")&.map { |child| child["key"] }&.sort
    canonical = children.each_with_index.map do |child, index|
      external_blockers = child.blocker_ids.reject { |id| id == parent.id || child_ids.include?(id) }
      canonical_child(
        key: approved_keys&.size == children.size ? approved_keys.fetch(index) : "position:#{index}",
        title: child.title,
        description_markdown: child.description_markdown,
        blocker_positions: child.blocker_ids.filter_map { |id| positions[id] }.sort,
        task_type_key: child.task_type.key,
        parent_blocker: child.blocker_ids.include?(parent.id),
        external_blocker_ids: external_blockers.sort
      )
    end
    {
      parent_id: parent.id,
      digest: children.any? ? digest(canonical) : nil,
      children: children.map do |child|
        {
          task: child,
          sibling_blocker_ids: child.blocker_ids.select { |id| child_ids.include?(id) }.sort
        }
      end
    }
  end

  private

  def lock_parent!(parent_id)
    # A write-first transaction serializes the parent on SQLite, where SELECT FOR UPDATE is ineffective.
    updated = Task.where(id: parent_id).update_all("updated_at = updated_at")
    raise ActiveRecord::RecordNotFound if updated.zero?

    Task.find(parent_id)
  end

  def normalize!(parent:, children:)
    raise InvalidDefinition, "task must be a built-in brief" unless parent.task_type.key == "brief"
    raise InvalidDefinition, "children must be a non-empty array" unless children.is_a?(Array) && children.any?
    raise InvalidDefinition, "child graph cannot contain more than #{MAX_CHILDREN} children" if children.size > MAX_CHILDREN

    normalized = children.map { |child| normalize_child!(child) }
    keys = normalized.map { |child| child.fetch("key") }
    raise InvalidDefinition, "child keys must be unique" unless keys.uniq.size == keys.size

    known_keys = keys.to_set
    normalized.each do |child|
      unknown = child.fetch("blocker_keys").reject { |key| known_keys.include?(key) }
      raise InvalidDefinition, "blocker_keys must reference children in the same graph" if unknown.any?
      raise InvalidDefinition, "a child cannot block itself" if child.fetch("blocker_keys").include?(child.fetch("key"))
    end
    edge_count = normalized.sum { |child| child.fetch("blocker_keys").size }
    raise InvalidDefinition, "child graph cannot contain more than #{MAX_EDGES} sibling edges" if edge_count > MAX_EDGES
    reject_cycles_and_depth!(normalized)

    normalized = normalized.sort_by { |child| child.fetch("key") }
    if JSON.generate("children" => normalized).bytesize > MAX_DEFINITION_BYTES
      raise InvalidDefinition, "child graph definition must be at most 1 MiB"
    end
    normalized
  end

  def create_dependency!(task:, blocker:)
    TaskDependency.create!(task:, blocker:)
  end

  def normalize_child!(child)
    raise InvalidDefinition, "each child must be an object" unless child.is_a?(Hash)
    child = child.stringify_keys
    raise InvalidDefinition, "each child must contain exactly key, title, description_markdown, and blocker_keys" unless
      child.keys.sort == REQUIRED_CHILD_KEYS.sort

    %w[key title description_markdown].each do |name|
      raise InvalidDefinition, "#{name} must be a non-empty string" unless child[name].is_a?(String) && child[name].present?
      raise InvalidDefinition, "#{name} must be valid UTF-8" unless valid_utf8?(child[name])
    end
    validate_field_size!(child.fetch("key"), "key", MAX_KEY_BYTES)
    validate_field_size!(child.fetch("title"), "title", MAX_TITLE_BYTES)
    validate_field_size!(child.fetch("description_markdown"), "description_markdown", MAX_DESCRIPTION_BYTES)
    blocker_keys = child.fetch("blocker_keys")
    unless blocker_keys.is_a?(Array) && blocker_keys.size <= MAX_EDGES &&
        blocker_keys.all? { |key| key.is_a?(String) && key.present? } && blocker_keys.uniq.size == blocker_keys.size
      raise InvalidDefinition, "blocker_keys must be an array of unique non-empty strings"
    end
    blocker_keys.each do |key|
      raise InvalidDefinition, "blocker key must be valid UTF-8" unless valid_utf8?(key)
      validate_field_size!(key, "blocker key", MAX_KEY_BYTES)
    end

    child.slice(*REQUIRED_CHILD_KEYS).merge("blocker_keys" => blocker_keys.sort)
  end

  def reject_cycles_and_depth!(children)
    dependents = children.to_h { |child| [ child.fetch("key"), [] ] }
    indegree = children.to_h { |child| [ child.fetch("key"), child.fetch("blocker_keys").size ] }
    depth = indegree.transform_values { 1 }
    children.each do |child|
      child.fetch("blocker_keys").each { |blocker| dependents.fetch(blocker) << child.fetch("key") }
    end
    ready = indegree.filter_map { |key, count| key if count.zero? }
    visited = 0
    until ready.empty?
      key = ready.shift
      visited += 1
      dependents.fetch(key).each do |dependent|
        depth[dependent] = [ depth.fetch(dependent), depth.fetch(key) + 1 ].max
        indegree[dependent] -= 1
        ready << dependent if indegree.fetch(dependent).zero?
      end
    end
    raise InvalidDefinition, "child graph cannot contain a dependency cycle" unless visited == children.size
    raise InvalidDefinition, "child graph cannot exceed depth #{MAX_DEPTH}" if depth.values.max > MAX_DEPTH
  end

  def valid_utf8?(value)
    value.encoding == Encoding::UTF_8 && value.valid_encoding?
  end

  def validate_field_size!(value, name, maximum)
    raise InvalidDefinition, "#{name} must be at most #{maximum} bytes" if value.bytesize > maximum
  end

  def validate_claim!(parent, owner_id:, claim_version:)
    valid = parent.status == "active" && parent.owner_id == owner_id && parent.claim_version == claim_version &&
      parent.current_step == "publish" && parent.lease_expires_at&.future?
    raise TaskLifecycle::Conflict, "brief claim is stale or not at the publication step" unless valid
  end

  def approved_definition!(parent)
    review = parent.accepted_artifacts["review"]
    graph = review && review["brief_graph"]
    digest = review && review["graph_digest"]
    unless review&.fetch("outcome", nil) == "approved" && graph.is_a?(Hash) && digest.is_a?(String)
      raise TaskLifecycle::Conflict, "brief review does not contain an approved graph identity"
    end

    definition = definition(parent:, children: graph["children"])
    unless definition.fetch("digest") == digest
      raise TaskLifecycle::Conflict, "approved graph identity is inconsistent"
    end
    definition
  end

  def definition_digest(normalized)
    positions = normalized.each_with_index.to_h { |child, index| [ child.fetch("key"), index ] }
    canonical = normalized.map do |child|
      canonical_child(
        key: child.fetch("key"),
        title: child.fetch("title"),
        description_markdown: child.fetch("description_markdown"),
        blocker_positions: child.fetch("blocker_keys").map { |key| positions.fetch(key) }.sort,
        task_type_key: "development",
        parent_blocker: true,
        external_blocker_ids: []
      )
    end
    digest(canonical)
  end

  def canonical_child(key:, title:, description_markdown:, blocker_positions:, task_type_key:, parent_blocker:,
    external_blocker_ids:)
    {
      "key" => key,
      "title" => title,
      "description_markdown" => description_markdown,
      "blocker_positions" => blocker_positions,
      "task_type_key" => task_type_key,
      "parent_blocker" => parent_blocker,
      "external_blocker_ids" => external_blocker_ids
    }
  end

  def digest(canonical)
    "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonical))}"
  end
end
