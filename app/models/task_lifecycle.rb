class TaskLifecycle
  UNCHANGED = Object.new.freeze

  class Error < StandardError; end
  class Conflict < Error; end
  class InvalidTransition < Error; end
  class InvalidInput < Error; end

  PAUSED_STATUSES = %w[needs_human blocked].freeze
  BUILT_IN_TASK_KEYS = %w[brief development fix].freeze
  BRIEF_POST_MATERIALIZATION_BACKWARD_OUTCOMES = %w[base_moved graph_invalid review_invalid].freeze
  MAX_ARTIFACT_BYTES = 1.megabyte
  MAX_CREATION_KEY_BYTES = 200
  CREATION_KEY_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/

  def initialize(clock: -> { Time.current }, lease_duration: Rails.application.config.x.kos.lease_duration)
    raise ArgumentError, "lease_duration must be positive" unless lease_duration.positive?

    @clock = clock
    @lease_duration = lease_duration
  end

  def create!(project:, task_type:, title:, description_markdown:, parent: nil, blockers: [])
    Task.transaction do
      reject_brief_child_definition!(parent)
      task_type = TaskType.find(task_type.id)
      task = Task.create!(project:, task_type:, workflow: task_type.workflow, parent:, title:, description_markdown:,
        current_step: task_type.workflow.first_step_id)
      blockers.each { |blocker| TaskDependency.create!(task:, blocker:) }
      task
    end
  end

  def show!(task_id)
    Task.find(task_id)
  end

  def update_definition!(task_id:, description_markdown: UNCHANGED, parent: UNCHANGED, blockers: UNCHANGED)
    Task.transaction do
      task = lock_editable_task!(task_id)
      proposed_parent = parent.equal?(UNCHANGED) ? task.parent : parent
      reject_brief_child_definition!(task.parent)
      reject_brief_child_definition!(proposed_parent)

      task.description_markdown = description_markdown unless description_markdown.equal?(UNCHANGED)
      task.parent = parent unless parent.equal?(UNCHANGED)
      task.save! if task.changed?

      unless blockers.equal?(UNCHANGED)
        task.task_dependencies.each(&:destroy!)
        blockers.each { |blocker| TaskDependency.create!(task:, blocker:) }
      end

      task
    end
  end

  def create_and_claim!(project:, task_type:, title:, description_markdown:, owner_id:, parent: nil, blockers: [],
    creation_key: nil)
    validate_owner!(owner_id)
    validate_creation_key!(creation_key) unless creation_key.nil?
    attributes = { project:, task_type:, title:, description_markdown:, parent:, blockers: }

    Task.transaction do
      if creation_key
        existing = find_by_creation_key(project:, task_type:, creation_key:)
        return verify_matching_definition!(existing, **attributes, conflict_identity: "creation key") if existing
      end

      existing = Task.find_by(owner_id:)
      if existing && creation_key && existing.creation_key != creation_key
        raise Conflict, "owner already identifies another task"
      end
      return verify_matching_definition!(existing, **attributes, conflict_identity: "owner") if existing

      create_claimed_task!(**attributes, owner_id:, creation_key:)
    end
  rescue ActiveRecord::RecordNotUnique
    if creation_key
      existing = find_by_creation_key(project:, task_type:, creation_key:)
      return verify_matching_definition!(existing, **attributes, conflict_identity: "creation key") if existing
    end

    existing = Task.find_by(owner_id:)
    raise Conflict, "owner already identifies another task" unless existing
    raise Conflict, "owner already identifies another task" if creation_key && existing.creation_key != creation_key

    verify_matching_definition!(existing, **attributes, conflict_identity: "owner")
  end

  def claim_next!(project:, owner_id:, task_type: nil)
    validate_owner!(owner_id)
    ensure_owner_available!(owner_id)

    loop do
      now = @clock.call
      eligible = eligible_tasks(project, task_type:)
      task_id = next_claimable_id(eligible)
      return if task_id.nil?

      claimed = claim_from_scope(eligible.where(id: task_id), task_id:, owner_id:, now:)
      return claimed if claimed
    end
  rescue ActiveRecord::RecordNotUnique
    raise Conflict, "owner already identifies another task"
  end

  def claim!(task_id:, owner_id:)
    validate_owner!(owner_id)
    task = Task.find(task_id)
    ensure_owner_available!(owner_id)
    now = @clock.call
    claimed = claim_from_scope(eligible_tasks(task.project).where(id: task.id), task_id: task.id, owner_id:, now:)
    raise Conflict, "task cannot be claimed from its current state" unless claimed

    claimed
  rescue ActiveRecord::RecordNotUnique
    raise Conflict, "owner already identifies another task"
  end

  def show_owned(project:, owner_id:)
    validate_owner!(owner_id)
    Task.find_by(project:, owner_id:, status: "active")
  end

  def resumable(project:, task_type:)
    Task.where(project:, task_type:, status: [ "active", *PAUSED_STATUSES ]).order(:created_at, :id)
  end

  def resume!(task_id:, owner_id:, claim_version:, step:, answer: nil, takeover_confirmed: false)
    validate_owner!(owner_id)
    validate_human_answer!(answer) unless answer.nil?
    task = Task.find(task_id)
    ensure_owner_available!(owner_id, task_id:)
    now = @clock.call
    fence = { id: task_id, claim_version:, current_step: step }
    Task.transaction do
      current = Task.where(fence).pick(:status)
      raise Conflict, "task claim is stale or does not match the current step" unless current

      if current == "needs_human" && answer.nil?
        raise InvalidInput, "answer must be present when resuming a needs_human task"
      end
      if current != "needs_human" && !answer.nil?
        raise InvalidInput, "answer is allowed only when resuming a needs_human task"
      end

      changes = {
        status: "active",
        owner_id:,
        claim_version: Arel.sql("claim_version + 1"),
        lease_expires_at: now + @lease_duration,
        updated_at: now
      }
      if current == "needs_human"
        changes.merge!(human_answer: answer, human_answer_step: step, human_answer_claim_version: claim_version)
      end

      resumable = Task.where(fence, status: PAUSED_STATUSES, pause_step: step, pause_claim_version: claim_version)
      active = Task.where(fence, status: "active")
      active = active.where("lease_expires_at <= ?", now) unless takeover_confirmed == true
      scope = PAUSED_STATUSES.include?(current) ? resumable : active
      updated = scope.update_all(changes)
      raise Conflict, "task cannot be resumed from its current state" unless updated == 1

      task.reload
    end
  rescue ActiveRecord::RecordNotUnique
    raise Conflict, "owner already identifies another task"
  end

  def report_attempt!(task_id:, owner_id:, claim_version:, step:, outcome:, artifact:, message: nil)
    validate_artifact!(artifact)
    Task.transaction do
      task = Task.includes(:task_type, :workflow).find(task_id)
      action = task.workflow.action_for(step, outcome)
      raise InvalidTransition, "outcome is not allowed for the reported step" unless action
      validate_pause_message!(message) if action["pause"]
      reject_invalid_builtin_completion!(task, step, action)
      validate_brief_publication_order!(task, step, outcome, owner_id:, claim_version:)

      now = @clock.call
      artifacts = task.accepted_artifacts.deep_dup
      artifacts[step] = {
        "outcome" => outcome,
        "markdown" => artifact,
        "accepted_claim_version" => claim_version,
        "reconstructed" => false
      }
      changes = transition_changes(action, task, now, message:).merge(accepted_artifacts: artifacts)
      current_claim = Task.where(id: task_id, status: "active", owner_id:, claim_version:, current_step: step)
        .where("lease_expires_at > ?", now)
      updated = current_claim.update_all(changes)
      raise Conflict, "task claim is stale or does not match the current step" unless updated == 1

      task.reload
    end
  end

  def cancel!(task_id:)
    now = @clock.call
    task = Task.where(id: task_id).where.not(status: %w[completed cancelled])
    Task.transaction do
      updated = task.update_all(
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
      raise Conflict, "task cannot be cancelled from its current state" unless updated == 1

      Task.find(task_id)
    end
  end

  private

  def lock_editable_task!(task_id)
    editable = Task.where(id: task_id, status: "pending", claim_version: 0)
    return Task.find(task_id) if editable.update_all("id = id") == 1

    Task.find(task_id)
    raise Conflict, "task definition can change only while the task is pending and unclaimed"
  end

  def eligible_tasks(project, task_type: nil)
    incomplete = TaskDependency.where(blocker_id: Task.where.not(status: "completed")).select(:task_id)
    tasks = Task.where(project:, status: "pending").where.not(id: incomplete)
    tasks = tasks.where(task_type:) if task_type
    tasks.order(:created_at, :id)
  end

  def next_claimable_id(eligible)
    eligible.pick(:id)
  end

  def claim_from_scope(scope, task_id:, owner_id:, now:)
    Task.transaction do
      updated = scope.update_all(
        status: "active",
        owner_id:,
        claim_version: Arel.sql("claim_version + 1"),
        lease_expires_at: now + @lease_duration,
        updated_at: now
      )
      Task.find(task_id) if updated == 1
    end
  end

  def ensure_owner_available!(owner_id, task_id: nil)
    owned = Task.find_by(owner_id:)
    return unless owned && owned.id != task_id.to_i

    raise Conflict, "owner already identifies another task"
  end

  def find_by_creation_key(project:, task_type:, creation_key:)
    Task.find_by(project:, task_type:, creation_key:)
  end

  def verify_matching_definition!(task, project:, task_type:, title:, description_markdown:, parent:, blockers:,
    conflict_identity:)
    matches = task.project_id == project.id && task.task_type_id == task_type.id && task.title == title &&
      task.description_markdown == description_markdown && task.parent_id == parent&.id &&
      task.blocker_ids.sort == blockers.map(&:id).sort
    raise Conflict, "#{conflict_identity} already identifies a task with a different definition" unless matches

    task
  end

  def create_claimed_task!(project:, task_type:, title:, description_markdown:, owner_id:, parent:, blockers:,
    creation_key:)
    reject_brief_child_definition!(parent)
    ensure_blockers_completed!(blockers)
    task_type = TaskType.find(task_type.id)
    now = @clock.call
    task = Task.create!(project:, task_type:, workflow: task_type.workflow, parent:, title:, description_markdown:,
      current_step: task_type.workflow.first_step_id, creation_key:)
    blockers.each { |blocker| TaskDependency.create!(task:, blocker:) }
    Task.where(id: task.id).update_all(status: "active", owner_id:, claim_version: 1,
      lease_expires_at: now + @lease_duration, updated_at: now)
    task.reload
  end

  def ensure_blockers_completed!(blockers)
    completed = Task.where(id: blockers.map(&:id), status: "completed").count
    raise Conflict, "task cannot be claimed while a blocker is incomplete" unless completed == blockers.size
  end

  def reject_brief_child_definition!(parent)
    return unless parent&.task_type&.key == "brief"

    raise Conflict, "brief child graphs can change only through materialization"
  end

  def transition_changes(action, task, now, message:)
    changes = {
      claim_version: Arel.sql("claim_version + 1"),
      pause_message: nil,
      pause_step: nil,
      pause_claim_version: nil,
      human_answer: nil,
      human_answer_step: nil,
      human_answer_claim_version: nil,
      updated_at: now
    }
    if action.key?("next_step")
      changes[:current_step] = action["next_step"]
    elsif action["pause"]
      changes.merge!(status: action["pause"], owner_id: nil, lease_expires_at: nil, pause_message: message,
        pause_step: task.current_step, pause_claim_version: task.claim_version + 1)
    elsif action["complete_task"]
      changes.merge!(status: "completed", owner_id: nil, lease_expires_at: nil)
    else
      raise InvalidTransition, "workflow outcome has no supported action"
    end
    changes
  end

  def reject_invalid_builtin_completion!(task, step, action)
    return unless BUILT_IN_TASK_KEYS.include?(task.task_type.key) && action["complete_task"] && step != "verify"

    raise InvalidTransition, "built-in tasks can complete only from verify; cancel and recreate this legacy task"
  end

  def validate_brief_publication_order!(task, step, outcome, owner_id:, claim_version:)
    return unless task.task_type.key == "brief" && step == "publish"

    lock_brief_publication_fence!(task, step:, owner_id:, claim_version:)

    children_exist = Task.where(parent_id: task.id).exists?
    if outcome == "published" && !children_exist
      raise InvalidTransition, "a brief cannot report published before its child graph is materialized"
    end
    if children_exist && BRIEF_POST_MATERIALIZATION_BACKWARD_OUTCOMES.include?(outcome)
      raise InvalidTransition, "a materialized brief graph cannot return publication to an earlier step"
    end
  end

  def lock_brief_publication_fence!(task, step:, owner_id:, claim_version:)
    now = @clock.call
    fenced = Task.where(id: task.id, status: "active", owner_id:, claim_version:, current_step: step)
      .where("lease_expires_at > ?", now)
    # Acquire SQLite's writer lock before observing children so materialization and reporting serialize.
    raise Conflict, "task claim is stale or does not match the current step" unless
      fenced.update_all("updated_at = updated_at") == 1
  end

  def validate_owner!(owner_id)
    raise ArgumentError, "owner_id must be present" if owner_id.blank?
  end

  def validate_creation_key!(creation_key)
    valid = creation_key.is_a?(String) && creation_key.bytesize.between?(1, MAX_CREATION_KEY_BYTES) &&
      creation_key.match?(CREATION_KEY_PATTERN)
    raise InvalidInput, "creation_key must be a safe nonblank string of at most 200 bytes" unless valid
  end

  def validate_artifact!(artifact)
    raise InvalidInput, "artifact must be a string" unless artifact.is_a?(String)
    raise InvalidInput, "artifact must be non-empty" if artifact.empty?
    raise InvalidInput, "artifact must be valid UTF-8" unless artifact.encoding == Encoding::UTF_8 && artifact.valid_encoding?
    raise InvalidInput, "artifact must be at most 1 MiB" if artifact.bytesize > MAX_ARTIFACT_BYTES
  end

  def validate_pause_message!(message)
    raise InvalidInput, "message must be a nonblank string for a pause" unless message.is_a?(String) && message.present?
  end

  def validate_human_answer!(answer)
    unless answer.is_a?(String) && answer.present? && answer.encoding == Encoding::UTF_8 && answer.valid_encoding?
      raise InvalidInput, "answer must be a nonblank valid UTF-8 string"
    end
  end
end
