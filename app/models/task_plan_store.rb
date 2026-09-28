class TaskPlanStore
  class InvalidDefinition < StandardError; end

  def replace!(project:, key:, title:, task_definitions:)
    definitions = normalize(task_definitions)
    validate_graph!(definitions)
    workflows = definitions.to_h do |definition|
      workflow_key = definition.fetch("workflow_key")
      workflow = Workflow.where(key: workflow_key).order(revision: :desc).first
      raise ActiveRecord::RecordNotFound, "Workflow not found for key=#{workflow_key.inspect}" unless workflow

      [ workflow_key, workflow ]
    end
    TaskPlan.transaction do
      plan = TaskPlan.find_or_initialize_by(project:, key:)
      if plan.persisted?
        unless TaskPlan.where(id: plan.id, status: "active").update_all("updated_at = updated_at") == 1
          raise TaskLifecycle::Conflict, "abandoned task plan cannot be replaced"
        end
        plan.reload
        plan.tasks.update_all("updated_at = updated_at")
        unless plan.tasks.where.not(status: "pending").none? && plan.tasks.where.not(version: 0).none? &&
            plan.tasks.where.not(claim_id: nil).none? && plan.tasks.all? { |task| task.accepted_results.empty? }
          raise TaskLifecycle::Conflict, "task plan can be replaced only while every task is unstarted"
        end
        plan.tasks.destroy_all
        plan.version += 1
      end
      plan.title = title
      plan.save!

      tasks = definitions.to_h do |definition|
        workflow = workflows.fetch(definition.fetch("workflow_key"))
        task = plan.tasks.create!(
          key: definition.fetch("key"), title: definition.fetch("title"),
          description_markdown: definition.fetch("description_markdown"), workflow:, current_step: workflow.first_step_id
        )
        [ definition.fetch("key"), task ]
      end
      definitions.each do |definition|
        definition.fetch("blocker_keys").each do |blocker_key|
          TaskDependency.create!(task: tasks.fetch(definition.fetch("key")), blocker: tasks.fetch(blocker_key))
        end
      end
      plan.reload
    end
  end

  private

  def normalize(task_definitions)
    raise InvalidDefinition, "tasks must be a non-empty array" unless task_definitions.is_a?(Array) && task_definitions.any?
    if task_definitions.length > CoordinationLimits::MAX_TASKS_PER_PLAN
      raise InvalidDefinition, "tasks must contain at most #{CoordinationLimits::MAX_TASKS_PER_PLAN} items"
    end

    definitions = task_definitions.map.with_index do |raw, index|
      definition = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      unless definition.is_a?(Hash) && definition.keys.map(&:to_s).sort ==
          %w[blocker_keys description_markdown key title workflow_key]
        raise InvalidDefinition, "task #{index} must contain exactly the required fields"
      end
      definition.stringify_keys.tap do |item|
        validate_text!(item["key"], "task #{index} key", CoordinationLimits::MAX_KEY_BYTES)
        validate_text!(item["title"], "task #{index} title", CoordinationLimits::MAX_NAME_BYTES)
        validate_text!(item["description_markdown"], "task #{index} description_markdown", CoordinationLimits::MAX_TEXT_BYTES)
        validate_text!(item["workflow_key"], "task #{index} workflow_key", CoordinationLimits::MAX_KEY_BYTES)
        unless item["blocker_keys"].is_a?(Array) && item["blocker_keys"].all? { |value| value.is_a?(String) && value.present? }
          raise InvalidDefinition, "task #{index} blocker_keys must be an array of nonblank strings"
        end
        item["blocker_keys"].each do |blocker|
          validate_text!(blocker, "task #{index} blocker key", CoordinationLimits::MAX_KEY_BYTES)
        end
        raise InvalidDefinition, "task #{index} blocker keys must be unique" unless
          item["blocker_keys"].uniq.length == item["blocker_keys"].length
      end
    end
    dependency_count = definitions.sum { |definition| definition.fetch("blocker_keys").length }
    if dependency_count > CoordinationLimits::MAX_DEPENDENCIES_PER_PLAN
      raise InvalidDefinition, "tasks must contain at most #{CoordinationLimits::MAX_DEPENDENCIES_PER_PLAN} dependencies"
    end
    definitions
  end

  def validate_graph!(definitions)
    keys = definitions.map { |definition| definition.fetch("key") }
    raise InvalidDefinition, "task keys must be unique" unless keys.uniq.length == keys.length

    edges = definitions.to_h { |definition| [ definition.fetch("key"), definition.fetch("blocker_keys") ] }
    missing = edges.values.flatten.uniq - keys
    raise InvalidDefinition, "unknown blocker key #{missing.first.inspect}" if missing.any?

    dependents = keys.to_h { |key| [ key, [] ] }
    indegrees = edges.transform_values(&:length)
    edges.each do |dependent, blockers|
      blockers.each { |blocker| dependents.fetch(blocker) << dependent }
    end
    pending = indegrees.filter_map { |key, count| key if count.zero? }
    visited_count = 0
    until pending.empty?
      key = pending.pop
      visited_count += 1
      dependents.fetch(key).each do |dependent|
        indegrees[dependent] -= 1
        pending << dependent if indegrees[dependent].zero?
      end
    end
    raise InvalidDefinition, "task dependencies must be acyclic" unless visited_count == keys.length
  end

  def validate_text!(value, label, max_bytes)
    return if CoordinationLimits.valid_text?(value, max_bytes:)

    raise InvalidDefinition, "#{label} must be a nonblank valid UTF-8 string of at most #{max_bytes} bytes"
  end
end
