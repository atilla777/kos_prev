class BuiltInCatalog
  PAUSES = {
    "needs_human" => { "pause" => "needs_human" },
    "blocked" => { "pause" => "blocked" }
  }.freeze

  def self.step(id, name, instruction, outcomes)
    { "id" => id, "name" => name, "instruction" => instruction, "outcomes" => outcomes.merge(PAUSES) }
  end
  private_class_method :step

  DEFINITIONS = {
    "development" => [
      step("plan", "Plan", "Plan the smallest coherent change and its verification.",
        "planned" => { "next_step" => "implement" }),
      step("implement", "Implement", "Implement the plan, run appropriate checks, and record the result.",
        "implemented" => { "next_step" => "review" }, "replan" => { "next_step" => "plan" }),
      step("review", "Review", "Review the complete change independently and report actionable findings.",
        "approved" => { "next_step" => "publish" }, "changes_requested" => { "next_step" => "implement" },
        "replan" => { "next_step" => "plan" }),
      step("publish", "Publish", "Publish the approved change and observe the result.",
        "published" => { "complete_task" => true }, "changes_requested" => { "next_step" => "implement" })
    ],
    "fix" => [
      step("diagnose", "Diagnose", "Reproduce the problem and identify an evidenced root cause.",
        "diagnosed" => { "next_step" => "plan" }),
      step("plan", "Plan", "Plan the smallest safe fix and regression verification.",
        "planned" => { "next_step" => "implement" }, "rediagnose" => { "next_step" => "diagnose" }),
      step("implement", "Implement", "Implement the fix, run appropriate checks, and record the result.",
        "implemented" => { "next_step" => "review" }, "replan" => { "next_step" => "plan" }),
      step("review", "Review", "Review the complete fix independently and report actionable findings.",
        "approved" => { "next_step" => "publish" }, "changes_requested" => { "next_step" => "implement" },
        "replan" => { "next_step" => "plan" }),
      step("publish", "Publish", "Publish the approved fix and observe the result.",
        "published" => { "complete_task" => true }, "changes_requested" => { "next_step" => "implement" })
    ],
    "brief" => [
      step("brief", "Brief", "Specify the requested behavior and propose a minimal task plan.",
        "specified" => { "next_step" => "review" }),
      step("review", "Review", "Review the specification and proposed task plan independently.",
        "approved" => { "next_step" => "publish" }, "changes_requested" => { "next_step" => "brief" }),
      step("publish", "Publish", "Publish the approved specification and store its task plan.",
        "published" => { "complete_task" => true }, "changes_requested" => { "next_step" => "brief" })
    ]
  }.freeze

  def self.install!
    Workflow.transaction do
      DEFINITIONS.each do |key, steps|
        Workflow.find_or_create_by!(key:, revision: 1) do |workflow|
          workflow.name = key.titleize
          workflow.definition_json = { "steps" => steps }
        end
      end
    end
  end

  def self.installed?
    DEFINITIONS.all? do |key, steps|
      Workflow.find_by(key:, revision: 1)&.definition_json == { "steps" => steps }
    end
  end

  def self.definitions
    DEFINITIONS.transform_values { |steps| { "steps" => steps } }
  end
end
