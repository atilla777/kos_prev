class Workflow < ApplicationRecord
  ROOT_KEYS = %w[steps].freeze
  STEP_KEYS = %w[artifact_template execution_mode id instruction model_tier name outcomes].freeze
  PREVIOUS_STEP_KEYS = %w[artifact_template id instruction model_tier name outcomes].freeze
  LEGACY_STEP_KEYS = %w[artifact_template id instruction name outcomes].freeze
  ACTION_KEYS = %w[complete_task next_step pause].freeze
  PAUSES = %w[blocked needs_human].freeze
  MODEL_TIERS = %w[standard advanced].freeze
  EXECUTION_MODES = %w[main subagent].freeze

  has_many :task_types
  has_many :tasks

  validate :definition_json_is_valid
  validate :definition_json_is_immutable, on: :update

  def step_ids
    return [] unless definition_json.is_a?(Hash) && definition_json["steps"].is_a?(Array)

    definition_json["steps"].filter_map { |step| step["id"] if step.is_a?(Hash) }
  end

  def first_step_id
    step_ids.first
  end

  def action_for(step_id, outcome)
    step = definition_json["steps"].find { |candidate| candidate["id"] == step_id }
    step&.dig("outcomes", outcome)
  end

  def step_for(step_id)
    definition_for_execution["steps"].find { |candidate| candidate["id"] == step_id }
  end

  def definition_for_execution
    definition_json.merge("steps" => definition_json["steps"].map do |step|
      step.merge(
        "model_tier" => step.fetch("model_tier", "advanced"),
        "execution_mode" => step.fetch("execution_mode", "subagent")
      )
    end)
  end

  private

  def definition_json_is_valid
    unless definition_json.is_a?(Hash) && definition_json.keys.sort == ROOT_KEYS
      errors.add(:definition_json, "must be an object containing only steps")
      return
    end

    steps = definition_json["steps"]
    unless steps.is_a?(Array) && steps.any?
      errors.add(:definition_json, "steps must be a non-empty array")
      return
    end

    ids = []
    targets = []
    steps.each_with_index do |step, index|
      validate_step(step, index, ids, targets)
    end

    errors.add(:definition_json, "step ids must be unique") if ids.uniq.length != ids.length
    targets.each do |target|
      errors.add(:definition_json, "next_step #{target.inspect} does not exist") unless ids.include?(target)
    end
    validate_reachable_completion(steps) if errors[:definition_json].empty?
  end

  def validate_step(step, index, ids, targets)
    unless step.is_a?(Hash) && valid_step_keys?(step.keys.sort)
      errors.add(:definition_json, "step #{index} must contain exactly the required fields")
      return
    end

    id = step["id"]
    ids << id if id.is_a?(String) && id.present?
    errors.add(:definition_json, "step #{index} id must be a non-empty string") unless id.is_a?(String) && id.present?
    errors.add(:definition_json, "step #{index} name must be a non-empty string") unless step["name"].is_a?(String) && step["name"].present?

    %w[instruction artifact_template].each do |field|
      errors.add(:definition_json, "step #{index} #{field} must be a string") unless step[field].is_a?(String)
    end
    unless MODEL_TIERS.include?(step.fetch("model_tier", "advanced"))
      errors.add(:definition_json, "step #{index} model_tier must be standard or advanced")
    end
    unless EXECUTION_MODES.include?(step.fetch("execution_mode", "subagent"))
      errors.add(:definition_json, "step #{index} execution_mode must be main or subagent")
    end

    validate_outcomes(step["outcomes"], index, targets)
  end

  def valid_step_keys?(keys)
    keys == STEP_KEYS || legacy_definition_unchanged? && [ PREVIOUS_STEP_KEYS, LEGACY_STEP_KEYS ].include?(keys)
  end

  def legacy_definition_unchanged?
    persisted? && !will_save_change_to_definition_json?
  end

  def validate_outcomes(outcomes, step_index, targets)
    unless outcomes.is_a?(Hash) && outcomes.any?
      errors.add(:definition_json, "step #{step_index} outcomes must be a non-empty object")
      return
    end

    outcomes.each do |name, action|
      errors.add(:definition_json, "outcome names must be non-empty strings") unless name.is_a?(String) && name.present?
      validate_action(action, step_index, name, targets)
    end
  end

  def validate_action(action, step_index, outcome_name, targets)
    unless action.is_a?(Hash) && action.keys.length == 1 && ACTION_KEYS.include?(action.keys.first)
      errors.add(:definition_json, "outcome #{outcome_name.inspect} in step #{step_index} must have exactly one action")
      return
    end

    key, value = action.first
    case key
    when "next_step"
      if value.is_a?(String) && value.present?
        targets << value
      else
        errors.add(:definition_json, "next_step must be a non-empty string")
      end
    when "pause"
      errors.add(:definition_json, "pause must be needs_human or blocked") unless PAUSES.include?(value)
    when "complete_task"
      errors.add(:definition_json, "complete_task must be true") unless value == true
    end
  end

  def validate_reachable_completion(steps)
    step_ids = steps.pluck("id")
    edges = steps.to_h do |step|
      [ step.fetch("id"), step.fetch("outcomes").values.filter_map { |action| action["next_step"] } ]
    end
    reachable = traverse([ step_ids.first ], edges)
    reverse_edges = step_ids.to_h { |id| [ id, [] ] }
    edges.each { |source, targets| targets.each { |target| reverse_edges.fetch(target) << source } }
    completion_steps = steps.filter_map do |step|
      step.fetch("id") if step.fetch("outcomes").values.any? { |action| action["complete_task"] == true }
    end
    can_complete = traverse(completion_steps, reverse_edges)
    missing = step_ids.select { |id| reachable.include?(id) && !can_complete.include?(id) }
    return if missing.empty?

    errors.add(:definition_json, "reachable steps without a path to complete_task: #{missing.join(", ")}")
  end

  def traverse(start_ids, edges)
    visited = {}
    pending = start_ids.dup
    until pending.empty?
      id = pending.pop
      next if visited[id]

      visited[id] = true
      pending.concat(edges.fetch(id))
    end
    visited
  end

  def definition_json_is_immutable
    return unless will_save_change_to_definition_json? && tasks.exists?

    errors.add(:definition_json, "cannot change after the workflow is used by a task")
  end
end
