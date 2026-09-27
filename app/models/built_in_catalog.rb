class BuiltInCatalog
  BRIEF_INSTRUCTION = "Use okf to specify the requested product behavior and propose the minimal acyclic development graph. Ask one precise needs_human question rather than inventing a material product decision. Integrate a moved base when returning from publication. Leave a clean linear local task-owned commit sequence from the observed base with exactly one raw line KOS-Task: <task-id> and no case variant or duplicate per commit; never push, validate, or materialize children."
  DIAGNOSE_INSTRUCTION = "Diagnose the reported problem without changing HEAD or the worktree. Reproduce repository code only from an exported temporary copy with an isolated environment and no ambient secrets. Establish an evidenced root cause, or use needs_human when expected behavior is ambiguous or the report cannot be reproduced."
  PLAN_INSTRUCTION = "Keep the repository unchanged and plan the smallest safe implementation with concrete verification. Validate relevant accepted evidence; for a fix require a sound diagnosis and a regression check that would fail for the diagnosed defect, otherwise choose diagnosis_invalid."
  IMPLEMENT_INSTRUCTION = "Validate the accepted plan and implement the smallest sound change, or choose plan_invalid. Integrate a moved base when needed. Run every required test, lint, formatting, build, and type check, fixing ordinary failures before success; report the structured required-check result and never report implemented unless it is passed or not_required. Leave a clean linear local task-owned commit sequence from the observed base with exactly one raw line KOS-Task: <task-id> and no case variant or duplicate per commit; never push."
  DOCUMENT_INSTRUCTION = "Confirm the implementation and required checks support documentation, or choose implementation_invalid. Use okf to update affected product behavior, or explain why behavior did not change. Commit documentation changes locally when needed, validate the complete clean linear task-owned sequence and exactly one raw line KOS-Task: <task-id> with no case variant or duplicate per commit, and never push."
  REVIEW_INSTRUCTION = "Independently review the accepted work and complete aggregate diff without changing HEAD, refs, index, worktree bytes, or status. Require a clean worktree and a nonempty contiguous linear single-parent sequence from the base to HEAD with exactly one raw line KOS-Task: <task-id> and no case variant or duplicate per commit. Prioritize correctness, security, regressions, invariants, and tests; require successful structured required-check evidence for development and fix work. Request changes for actionable findings, use redesign_required for an invalid plan, and approve only when none remain. Approval records the exact base, ordered commits, tip, base and per-commit trees, changed paths, and SHA-256 digest of the complete binary diff produced without external diff drivers or textconv."
  BRIEF_REVIEW_INSTRUCTION = "Independently review the product specification, proposed minimal acyclic graph, and complete aggregate diff without changing HEAD, refs, index, worktree bytes, or status. Require a clean worktree and a nonempty contiguous linear single-parent sequence from the base to HEAD with exactly one raw line KOS-Task: <task-id> and no case variant or duplicate per commit. Require the graph to fit the server limits, return changes_requested for any actionable specification, graph, history, or content finding, and approve only when none remain. An approved report supplies the exact graph through brief_graph so KOS records its normalized graph_digest, plus the exact base, ordered commits, tip, base and per-commit trees, changed paths, and SHA-256 digest of the complete binary diff produced without external diff drivers or textconv."
  PUBLISH_INSTRUCTION = "Never change local history or content. Validate accepted predecessor evidence and the approved exact base, ordered commits, tip, trees, paths, recomputed binary diff digest, clean state, linear topology, canonical KOS-Task trailers, and required-check evidence; mismatch returns review_invalid. Fetch the default branch. Treat an exact reviewed remote tip and sequence as already published; push the exact tip without force only when the remote equals the reviewed base; a remote matching neither returns base_moved without mutation. Fetch after every push result and report published only after observing the exact approved sequence remotely."
  BRIEF_PUBLISH_INSTRUCTION = "Never change local history or content. Validate the reviewed specification and graph plus the clean worktree, nonempty contiguous linear single-parent sequence, exact base, ordered commits, tip, base and per-commit trees, paths, recomputed binary diff digest, and exactly one raw line KOS-Task: <task-id> with no case variant or duplicate per commit; mismatch returns review_invalid. Fetch the default branch, accept an exact reviewed remote tip and sequence, or push the exact tip without force only from the reviewed base; a remote matching neither returns base_moved without mutation. Fetch after every push result and require the exact approved commits and trees remotely. Then atomically materialize the approved child graph through the fenced KOS operation. An exact retry returns unchanged; a conflicting identity stops, and an observed wrong graph returns graph_invalid so KOS atomically retracts only the unstarted graph. Report published only after observation equals the approved graph_digest."

  COMMON_OUTCOMES = {
    "needs_human" => { "pause" => "needs_human" },
    "blocked" => { "pause" => "blocked" }
  }.freeze

  CATALOG = {
    "brief" => {
      name: "Brief",
      workflow_name: "Built-in brief",
      steps: [
        [ "brief", "Brief", "main", "advanced", BRIEF_INSTRUCTION,
          "# Brief\n\n## Specification\n\n## Proposed task graph\n\n## Commit sequence", { "specified" => { "next_step" => "review" } } ],
        [ "review", "Review", "subagent", "advanced", BRIEF_REVIEW_INSTRUCTION,
          "# Review\n\n## Graph identity\n\n## Findings\n\n## Decision", { "approved" => { "next_step" => "publish" },
            "changes_requested" => { "next_step" => "brief" } } ],
        [ "publish", "Publish", "subagent", "standard", BRIEF_PUBLISH_INSTRUCTION,
          "# Publication\n\n## Reviewed commit sequence\n\n## Remote observation\n\n## Child graph", { "published" => { "complete_task" => true },
            "review_invalid" => { "next_step" => "review" }, "base_moved" => { "next_step" => "brief" },
            "graph_invalid" => { "next_step" => "brief" } } ]
      ]
    },
    "development" => {
      name: "Development",
      workflow_name: "Built-in development",
      steps: [
        [ "plan", "Plan", "subagent", "advanced", PLAN_INSTRUCTION,
          "# Plan\n\n## Scope\n\n## Implementation\n\n## Verification", { "planned" => { "next_step" => "implement" } } ],
        [ "implement", "Implement", "subagent", "standard", IMPLEMENT_INSTRUCTION,
          "# Implementation\n\n## Changes\n\n## Checks\n\n## Commit sequence", { "implemented" => { "next_step" => "document" },
            "plan_invalid" => { "next_step" => "plan" } } ],
        [ "document", "Document", "subagent", "standard", DOCUMENT_INSTRUCTION,
          "# Documentation\n\n## Product behavior", { "documented" => { "next_step" => "review" },
            "implementation_invalid" => { "next_step" => "implement" } } ],
        [ "review", "Review", "subagent", "advanced", REVIEW_INSTRUCTION,
          "# Review\n\n## Commit sequence\n\n## Trees and diff digest\n\n## Findings\n\n## Decision", { "approved" => { "next_step" => "publish" },
            "changes_requested" => { "next_step" => "implement" }, "redesign_required" => { "next_step" => "plan" } } ],
        [ "publish", "Publish", "subagent", "standard", PUBLISH_INSTRUCTION,
          "# Publication\n\n## Reviewed commit sequence\n\n## Remote observation", { "published" => { "complete_task" => true },
            "review_invalid" => { "next_step" => "review" }, "base_moved" => { "next_step" => "implement" } } ]
      ]
    },
    "fix" => {
      name: "Fix",
      workflow_name: "Built-in fix",
      steps: [
        [ "diagnose", "Diagnose", "subagent", "advanced", DIAGNOSE_INSTRUCTION,
          "# Diagnosis\n\n## Reproduction\n\n## Evidence\n\n## Root cause", { "diagnosed" => { "next_step" => "plan" } } ],
        [ "plan", "Plan", "subagent", "advanced", PLAN_INSTRUCTION,
          "# Plan\n\n## Fix\n\n## Regression check", { "planned" => { "next_step" => "implement" },
            "diagnosis_invalid" => { "next_step" => "diagnose" } } ],
        [ "implement", "Implement", "subagent", "standard", IMPLEMENT_INSTRUCTION,
          "# Implementation\n\n## Changes\n\n## Checks\n\n## Commit sequence", { "implemented" => { "next_step" => "document" },
            "plan_invalid" => { "next_step" => "plan" } } ],
        [ "document", "Document", "subagent", "standard", DOCUMENT_INSTRUCTION,
          "# Documentation\n\n## Product behavior", { "documented" => { "next_step" => "review" },
            "implementation_invalid" => { "next_step" => "implement" } } ],
        [ "review", "Review", "subagent", "advanced", REVIEW_INSTRUCTION,
          "# Review\n\n## Commit sequence\n\n## Trees and diff digest\n\n## Findings\n\n## Decision", { "approved" => { "next_step" => "publish" },
            "changes_requested" => { "next_step" => "implement" }, "redesign_required" => { "next_step" => "plan" } } ],
        [ "publish", "Publish", "subagent", "standard", PUBLISH_INSTRUCTION,
          "# Publication\n\n## Reviewed commit sequence\n\n## Remote observation", { "published" => { "complete_task" => true },
            "review_invalid" => { "next_step" => "review" }, "base_moved" => { "next_step" => "implement" } } ]
      ]
    }
  }.freeze

  def self.install!
    TaskType.transaction do
      existing = TaskType.where(key: CATALOG.keys).index_by(&:key)
      unless existing.empty? || existing.keys.sort == CATALOG.keys.sort
        record = existing.values.first
        record.errors.add(:key, "built-in task type catalog is only partially installed")
        raise ActiveRecord::RecordInvalid, record
      end

      CATALOG.each do |key, entry|
        definition = definition_for(entry.fetch(:steps))
        task_type = existing[key]
        next if task_type&.workflow&.definition_json == definition

        workflow = Workflow.create!(name: entry.fetch(:workflow_name), definition_json: definition)
        if task_type
          task_type.update_builtin!(name: entry.fetch(:name), workflow:)
        else
          TaskType.create_builtin!(key:, name: entry.fetch(:name), workflow:)
        end
      end
    end
  end

  def self.definitions
    CATALOG.transform_values { |entry| definition_for(entry.fetch(:steps)) }
  end

  def self.definition_for(steps)
    { "steps" => steps.map do |id, name, execution_mode, model_tier, instruction, artifact_template, outcomes|
      {
        "id" => id,
        "name" => name,
        "execution_mode" => execution_mode,
        "model_tier" => model_tier,
        "instruction" => instruction,
        "artifact_template" => artifact_template,
        "outcomes" => outcomes.merge(COMMON_OUTCOMES)
      }
    end }
  end
  private_class_method :definition_for
end
