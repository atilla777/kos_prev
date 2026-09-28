class Workflow < ApplicationRecord
  ROOT_KEYS = %w[steps].freeze
  STEP_KEYS = %w[id instruction name outcomes].freeze
  ACTION_KEYS = %w[complete_task next_step pause].freeze
  PAUSES = %w[blocked needs_human].freeze

  has_many :tasks

  validates :key, presence: true, format: { with: /\A[a-z][a-z0-9_-]*\z/ }, uniqueness: { scope: :revision }
  validates :name, presence: true
  validates :key, bounded_text: { maximum: CoordinationLimits::MAX_KEY_BYTES }
  validates :name, bounded_text: { maximum: CoordinationLimits::MAX_NAME_BYTES }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validate :definition_json_is_valid
  validate :revision_is_immutable, on: :update

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
    definition_json["steps"].find { |candidate| candidate["id"] == step_id }
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
    if steps.length > CoordinationLimits::MAX_STEPS_PER_WORKFLOW
      errors.add(:definition_json, "must contain at most #{CoordinationLimits::MAX_STEPS_PER_WORKFLOW} steps")
      return
    end

    ids = []
    targets = []
    outcome_count = 0
    steps.each_with_index do |step, index|
      outcome_count += validate_step(step, index, ids, targets)
    end
    errors.add(:definition_json, "must contain at most #{CoordinationLimits::MAX_OUTCOMES_PER_WORKFLOW} outcomes") if
      outcome_count > CoordinationLimits::MAX_OUTCOMES_PER_WORKFLOW

    errors.add(:definition_json, "step ids must be unique") if ids.uniq.length != ids.length
    targets.each do |target|
      errors.add(:definition_json, "next_step #{target.inspect} does not exist") unless ids.include?(target)
    end
    validate_reachable_completion(steps) if errors[:definition_json].empty?
  end

  def validate_step(step, index, ids, targets)
    unless step.is_a?(Hash) && step.keys.sort == STEP_KEYS
      errors.add(:definition_json, "step #{index} must contain exactly the required fields")
      return 0
    end

    id = step["id"]
    ids << id if valid_definition_text?(id, CoordinationLimits::MAX_KEY_BYTES)
    errors.add(:definition_json, "step #{index} id must be a non-empty valid UTF-8 string of at most 100 bytes") unless
      valid_definition_text?(id, CoordinationLimits::MAX_KEY_BYTES)
    errors.add(:definition_json, "step #{index} name must be a non-empty valid UTF-8 string of at most 200 bytes") unless
      valid_definition_text?(step["name"], CoordinationLimits::MAX_NAME_BYTES)
    errors.add(:definition_json, "step #{index} instruction must be a non-empty valid UTF-8 string of at most 16 KiB") unless
      valid_definition_text?(step["instruction"], CoordinationLimits::MAX_TEXT_BYTES)

    validate_outcomes(step["outcomes"], index, targets)
  end

  def validate_outcomes(outcomes, step_index, targets)
    unless outcomes.is_a?(Hash) && outcomes.any?
      errors.add(:definition_json, "step #{step_index} outcomes must be a non-empty object")
      return 0
    end

    outcomes.each do |name, action|
      errors.add(:definition_json, "outcome names must be non-empty valid UTF-8 strings of at most 100 bytes") unless
        valid_definition_text?(name, CoordinationLimits::MAX_KEY_BYTES)
      validate_action(action, step_index, name, targets)
    end
    outcomes.length
  end

  def validate_action(action, step_index, outcome_name, targets)
    unless action.is_a?(Hash) && action.keys.length == 1 && ACTION_KEYS.include?(action.keys.first)
      errors.add(:definition_json, "outcome #{outcome_name.inspect} in step #{step_index} must have exactly one action")
      return
    end

    key, value = action.first
    case key
    when "next_step"
      if valid_definition_text?(value, CoordinationLimits::MAX_KEY_BYTES)
        targets << value
      else
        errors.add(:definition_json, "next_step must be a non-empty valid UTF-8 string of at most 100 bytes")
      end
    when "pause"
      errors.add(:definition_json, "pause must be needs_human or blocked") unless PAUSES.include?(value)
    when "complete_task"
      errors.add(:definition_json, "complete_task must be true") unless value == true
    end
  end

  def valid_definition_text?(value, max_bytes)
    CoordinationLimits.valid_text?(value, max_bytes:)
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

  def revision_is_immutable
    %w[key name revision definition_json].each do |attribute|
      errors.add(attribute, "cannot change on an immutable workflow revision") if will_save_change_to_attribute?(attribute)
    end
  end
end
