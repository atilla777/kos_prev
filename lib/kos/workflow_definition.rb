require "json"
require "coordination_limits"

module Kos
  module WorkflowDefinition
    ROOT_KEYS = %w[steps].freeze
    STEP_KEYS = %w[id instruction name outcomes].freeze
    ACTION_KEYS = %w[complete_task next_step pause].freeze
    PAUSES = %w[blocked needs_human].freeze

    CONTRACT = {
      "type" => "object",
      "required_fields" => ROOT_KEYS,
      "additional_fields" => false,
      "steps" => {
        "type" => "array", "minimum" => 1, "maximum" => CoordinationLimits::MAX_STEPS_PER_WORKFLOW,
        "item" => {
          "type" => "object", "required_fields" => STEP_KEYS, "additional_fields" => false,
          "fields" => {
            "id" => { "type" => "nonblank_utf8_string", "maximum_bytes" => CoordinationLimits::MAX_KEY_BYTES },
            "name" => { "type" => "nonblank_utf8_string", "maximum_bytes" => CoordinationLimits::MAX_NAME_BYTES },
            "instruction" => { "type" => "nonblank_utf8_string", "maximum_bytes" => CoordinationLimits::MAX_TEXT_BYTES },
            "outcomes" => {
              "type" => "nonempty_object", "name_type" => "nonblank_utf8_string",
              "name_maximum_bytes" => CoordinationLimits::MAX_KEY_BYTES,
              "total_maximum" => CoordinationLimits::MAX_OUTCOMES_PER_WORKFLOW,
              "value" => { "exactly_one" => [
                { "next_step" => { "type" => "existing_step_id",
                                    "maximum_bytes" => CoordinationLimits::MAX_KEY_BYTES } },
                { "pause" => { "enum" => PAUSES } },
                { "complete_task" => { "const" => true } }
              ] }
            }
          }
        }
      },
      "rules" => [
        "Step ids are unique.",
        "The first step is the initial step.",
        "Every next_step names an existing step.",
        "Every step reachable from the initial step has a path to complete_task."
      ]
    }.freeze

    EXAMPLE = {
      "steps" => [ {
        "id" => "work",
        "name" => "Work",
        "instruction" => "Perform the task description and report the observed result.",
        "outcomes" => {
          "completed" => { "complete_task" => true },
          "question" => { "pause" => "needs_human" },
          "blocked" => { "pause" => "blocked" }
        }
      } ]
    }.freeze

    module_function

    def contract
      deep_copy(CONTRACT)
    end

    def example
      deep_copy(EXAMPLE)
    end

    def errors(definition)
      messages = []
      unless definition.is_a?(Hash) && definition.keys.sort == ROOT_KEYS
        return [ "must be an object containing only steps" ]
      end

      steps = definition["steps"]
      return [ "steps must be a non-empty array" ] unless steps.is_a?(Array) && steps.any?
      if steps.length > CoordinationLimits::MAX_STEPS_PER_WORKFLOW
        return [ "must contain at most #{CoordinationLimits::MAX_STEPS_PER_WORKFLOW} steps" ]
      end

      ids = []
      targets = []
      outcome_count = steps.each_with_index.sum { |step, index| validate_step(step, index, ids, targets, messages) }
      if outcome_count > CoordinationLimits::MAX_OUTCOMES_PER_WORKFLOW
        messages << "must contain at most #{CoordinationLimits::MAX_OUTCOMES_PER_WORKFLOW} outcomes"
      end
      messages << "step ids must be unique" if ids.uniq.length != ids.length
      targets.each { |target| messages << "next_step #{target.inspect} does not exist" unless ids.include?(target) }
      validate_reachable_completion(steps, messages) if messages.empty?
      messages
    end

    def validate_step(step, index, ids, targets, messages)
      unless step.is_a?(Hash) && step.keys.sort == STEP_KEYS
        messages << "step #{index} must contain exactly the required fields"
        return 0
      end

      id = step["id"]
      ids << id if valid_text?(id, CoordinationLimits::MAX_KEY_BYTES)
      messages << "step #{index} id must be a non-empty valid UTF-8 string of at most 100 bytes" unless
        valid_text?(id, CoordinationLimits::MAX_KEY_BYTES)
      messages << "step #{index} name must be a non-empty valid UTF-8 string of at most 200 bytes" unless
        valid_text?(step["name"], CoordinationLimits::MAX_NAME_BYTES)
      messages << "step #{index} instruction must be a non-empty valid UTF-8 string of at most 16 KiB" unless
        valid_text?(step["instruction"], CoordinationLimits::MAX_TEXT_BYTES)
      validate_outcomes(step["outcomes"], index, targets, messages)
    end

    def validate_outcomes(outcomes, step_index, targets, messages)
      unless outcomes.is_a?(Hash) && outcomes.any?
        messages << "step #{step_index} outcomes must be a non-empty object"
        return 0
      end

      outcomes.each do |name, action|
        messages << "outcome names must be non-empty valid UTF-8 strings of at most 100 bytes" unless
          valid_text?(name, CoordinationLimits::MAX_KEY_BYTES)
        validate_action(action, step_index, name, targets, messages)
      end
      outcomes.length
    end

    def validate_action(action, step_index, outcome_name, targets, messages)
      unless action.is_a?(Hash) && action.keys.length == 1 && ACTION_KEYS.include?(action.keys.first)
        messages << "outcome #{outcome_name.inspect} in step #{step_index} must have exactly one action"
        return
      end

      key, value = action.first
      case key
      when "next_step"
        valid_text?(value, CoordinationLimits::MAX_KEY_BYTES) ? targets << value :
          messages << "next_step must be a non-empty valid UTF-8 string of at most 100 bytes"
      when "pause"
        messages << "pause must be needs_human or blocked" unless PAUSES.include?(value)
      when "complete_task"
        messages << "complete_task must be true" unless value == true
      end
    end

    def validate_reachable_completion(steps, messages)
      step_ids = steps.map { |step| step.fetch("id") }
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
      messages << "reachable steps without a path to complete_task: #{missing.join(", ")}" if missing.any?
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

    def valid_text?(value, maximum)
      CoordinationLimits.valid_text?(value, max_bytes: maximum)
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end
  end
end
