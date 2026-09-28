class Workflow < ApplicationRecord
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
    Kos::WorkflowDefinition.errors(definition_json).each { |message| errors.add(:definition_json, message) }
  end

  def revision_is_immutable
    %w[key name revision definition_json].each do |attribute|
      errors.add(attribute, "cannot change on an immutable workflow revision") if will_save_change_to_attribute?(attribute)
    end
  end
end
