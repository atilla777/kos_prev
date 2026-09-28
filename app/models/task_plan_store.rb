class TaskPlanStore
  class InvalidDefinition < StandardError; end

  def replace!(project:, key:, title:, task_definitions:)
    definitions = normalize(task_definitions)
    workflows = definitions.to_h do |definition|
      workflow_key = definition.fetch("workflow_key")
      [ workflow_key, Workflow.where(key: workflow_key).order(revision: :desc).first! ]
    end
    validate_graph!(definitions)

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

    task_definitions.map.with_index do |raw, index|
      definition = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      unless definition.is_a?(Hash) && definition.keys.map(&:to_s).sort ==
          %w[blocker_keys description_markdown key title workflow_key]
        raise InvalidDefinition, "task #{index} must contain exactly the required fields"
      end
      definition.stringify_keys.tap do |item|
        %w[key title description_markdown workflow_key].each do |field|
          raise InvalidDefinition, "task #{index} #{field} must be a nonblank string" unless
            item[field].is_a?(String) && item[field].present?
        end
        unless item["blocker_keys"].is_a?(Array) && item["blocker_keys"].all? { |value| value.is_a?(String) && value.present? }
          raise InvalidDefinition, "task #{index} blocker_keys must be an array of nonblank strings"
        end
      end
    end
  end

  def validate_graph!(definitions)
    keys = definitions.map { |definition| definition.fetch("key") }
    raise InvalidDefinition, "task keys must be unique" unless keys.uniq.length == keys.length

    edges = definitions.to_h { |definition| [ definition.fetch("key"), definition.fetch("blocker_keys") ] }
    missing = edges.values.flatten.uniq - keys
    raise InvalidDefinition, "unknown blocker key #{missing.first.inspect}" if missing.any?

    visiting = {}
    visited = {}
    visit = lambda do |key|
      raise InvalidDefinition, "task dependencies must be acyclic" if visiting[key]
      return if visited[key]

      visiting[key] = true
      edges.fetch(key).each { |blocker| visit.call(blocker) }
      visiting.delete(key)
      visited[key] = true
    end
    keys.each { |key| visit.call(key) }
  end
end
