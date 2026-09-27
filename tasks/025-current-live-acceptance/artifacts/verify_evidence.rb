#!/usr/bin/env ruby

require "digest"
require "json"
require "open3"
require "tmpdir"
require "time"

ARTIFACTS = File.expand_path(__dir__)

def run(*command, chdir: nil)
  output, error, status = Open3.capture3(*command, **(chdir ? { chdir: } : {}))
  raise "#{command.join(" ")} failed: #{error}" unless status.success?

  output
end

def assert(label, condition)
  raise "FAIL #{label}" unless condition

  puts "PASS #{label}"
end

def artifact(name)
  JSON.parse(File.read(File.join(ARTIFACTS, name)))
end

def git(repository, *arguments)
  run("git", "--no-pager", *arguments, chdir: repository)
end

def review_identity(task_id)
  markdown = artifact("task-#{task_id}-review.json").fetch("markdown")
  base = markdown[/\bBase: `([0-9a-f]{40})`/, 1]
  tip = markdown[/\bTip: `([0-9a-f]{40})`/, 1]
  digest = markdown.lines.find { |line| line.match?(/SHA-256/i) }&.scan(/[0-9a-f]{64}/)&.last
  paths = markdown[/Changed paths?: ([^\n]+)/, 1]&.scan(/`([^`]+)`/)&.flatten&.sort
  trees = markdown.lines.grep(/tree:/i).filter_map { |line| line.scan(/[0-9a-f]{40}/).last }
  raise "task #{task_id} review identity is incomplete" unless base && tip && digest && paths && !trees.empty?

  { markdown:, base:, tip:, digest:, paths:, trees: }
end

expected_inventory = %w[
  agents/kos-step-advanced.md
  agents/kos-step-standard.md
  commands/kos-brief.md
  commands/kos-fix.md
  commands/kos-task.md
  commands/kos.md
  kos-installation.json
  skills/kos-cli/SKILL.md
  skills/kos-git/SKILL.md
  skills/kos-step/SKILL.md
  skills/kos/SKILL.md
  skills/okf/SKILL.md
]
inventory = File.readlines(File.join(ARTIFACTS, "installed-inventory.txt"), chomp: true)
assert("installed generic inventory", inventory == expected_inventory)
manifest = artifact("kos-installation.json")
provenance = artifact("provenance.json")
assert("common source identity", manifest.fetch("source_id") == provenance.fetch("source_id") &&
  File.read(File.join(ARTIFACTS, "cli-help.txt")).include?(provenance.fetch("source_id")))

(1..4).each do |task_id|
  context = artifact("task-#{task_id}-context.json")
  task = context.fetch("task")
  expected_step = task_id == 4 ? "advanced_probe" : "publish"
  assert("task #{task_id} completed with released ownership", task.fetch("status") == "completed" &&
    task.fetch("current_step") == expected_step && task["owner_id"].nil? && task["lease_expires_at"].nil?)
  context.fetch("artifacts").each do |entry|
    accepted = artifact("task-#{task_id}-#{entry.fetch("step")}.json")
    assert("task #{task_id} #{entry.fetch("step")} matches index", accepted.fetch("outcome") == entry.fetch("outcome") &&
      accepted.fetch("accepted_claim_version") == entry.fetch("accepted_claim_version"))
  end
end

[ 2, 3 ].each do |task_id|
  implementation = artifact("task-#{task_id}-implement.json")
  context_entry = artifact("task-#{task_id}-context.json").fetch("artifacts").find { |entry| entry.fetch("step") == "implement" }
  assert("task #{task_id} required checks passed", implementation.fetch("required_checks") == "passed" &&
    context_entry.fetch("required_checks") == "passed")
end

children = artifact("task-1-children.json")
review = artifact("task-1-review.json")
definition = review.fetch("brief_graph").fetch("children")
normalized = definition.sort_by { |child| child.fetch("key") }.map do |child|
  {
    "key" => child.fetch("key"),
    "title" => child.fetch("title"),
    "description_markdown" => child.fetch("description_markdown"),
    "blocker_positions" => [],
    "task_type_key" => "development",
    "parent_blocker" => true,
    "external_blocker_ids" => []
  }
end
digest = "sha256:#{Digest::SHA256.hexdigest(JSON.generate(normalized))}"
child = children.fetch("children").fetch(0)
assert("brief graph identity", children.fetch("children").length == 1 && children.fetch("digest") == digest &&
  review.fetch("graph_digest") == digest)
assert("brief child completed without sibling blockers", child.dig("task", "id") == 2 &&
  child.dig("task", "status") == "completed" && child.dig("task", "parent_id") == 1 &&
  child.dig("task", "blocker_ids") == [ 1 ] && child.fetch("sibling_blocker_ids").empty?)

launches = artifact("agent-launches.json")
all_launches = launches.fetch("main") + launches.fetch("calls")
assert("all dispatched prompts are ID-only", all_launches.all? { |call| call.fetch("prompt").match?(/\A[1-5]\z/) })
assert("standard profile uses Terra", launches.fetch("calls").select { |call| call.fetch("profile") == "kos-step-standard" }
  .all? { |call| call.fetch("model") == "gpt-5.6-terra" })
assert("advanced profile uses Sol", launches.fetch("calls").select { |call| call.fetch("profile") == "kos-step-advanced" }
  .all? { |call| call.fetch("model") == "gpt-5.6-sol" })
assert("custom main uses fixed Sol agent", launches.fetch("main").any? do |call|
  call.fetch("source") == "kos-custom" && call.fetch("prompt") == "4" && call.fetch("model") == "gpt-5.6-sol"
end)
assert("main observations are bound to successful live reports", launches.fetch("main").length == 3 &&
  launches.fetch("main").all? do |call|
    call.fetch("timestamp").positive? && call.fetch("raw_line_sha256").match?(/\A[0-9a-f]{64}\z/) &&
      call.fetch("result") == "reported"
  end)
assert("unchanged executions are retained", launches.fetch("calls").count { |call| call.fetch("result") == "stale_rejected" } == 4)
assert("launch observations retain raw stream audit commitments", launches.fetch("streams").length == 8 &&
  launches.fetch("streams").all? { |stream| stream.fetch("sha256").match?(/\A[0-9a-f]{64}\z/) && stream.fetch("lines").positive? })

command_source = File.read(File.expand_path("../../../.opencode/commands/kos-task.md", __dir__))
standard_source = File.read(File.expand_path("../../../.opencode/agents/kos-step-standard.md", __dir__))
advanced_source = File.read(File.expand_path("../../../.opencode/agents/kos-step-advanced.md", __dir__))
assert("installed source declares custom Sol main", command_source.include?("model: openai/gpt-5.6-sol"))
assert("installed source declares generic model tiers", standard_source.include?("model: openai/gpt-5.6-terra") &&
  advanced_source.include?("model: openai/gpt-5.6-sol"))

observations = launches.fetch("scheduler")
stale_calls = launches.fetch("calls").select { |call| call.fetch("result") == "stale_rejected" }
stale_calls.each do |call|
  task_id = call.fetch("prompt").to_i
  before = observations.select do |observation|
    observation.fetch("source") == call.fetch("source") && observation.fetch("timestamp") < call.fetch("timestamp") &&
      observation.fetch("command").match?(/task show ["']?#{task_id}["']?\b/)
  end.max_by { |observation| observation.fetch("timestamp") }
  after = observations.select do |observation|
    observation.fetch("source") == call.fetch("source") && observation.fetch("timestamp") > call.fetch("timestamp") &&
      observation.fetch("command").match?(/task show ["']?#{task_id}["']?\b/)
  end.min_by { |observation| observation.fetch("timestamp") }
  assert("#{call.fetch("source")} stale dispatch has unchanged authoritative observation", before && after &&
    JSON.parse(before.fetch("output")).fetch("task") == JSON.parse(after.fetch("output")).fetch("task"))
end

recovery = artifact("interventions.json").fetch("expired_lease_recovery")
probe = artifact("task-5-context.json")
probe_artifact = artifact("task-5-main_probe.json")
assert("expired lease resumed exactly once", recovery.fetch("resume_operations") == 1 &&
  recovery.dig("before", "claim_version") == 1 && recovery.dig("resume", "claim_version") == 2 &&
  probe_artifact.fetch("accepted_claim_version") == 2)
resume_observations = observations.select { |observation| observation.fetch("command").match?(/task resume 5\b/) }
resume_observation = resume_observations.fetch(0)
resume_result = JSON.parse(resume_observation.fetch("output")).fetch("task")
assert("expired lease observation proves one exact resume", resume_observations.length == 1 &&
  resume_observation.fetch("command").include?("--claim-version 1 --step main_probe") &&
  Time.at(resume_observation.fetch("timestamp") / 1000.0).utc > Time.parse(recovery.dig("before", "lease_expires_at")) &&
  resume_result.fetch("claim_version") == 2 && resume_result.fetch("current_step") == "main_probe")
assert("recovery probe released ownership", probe.dig("task", "status") == "cancelled" &&
  probe.dig("task", "owner_id").nil? && probe.dig("task", "claim_version") == 4)
assert("recovery did not change remote", recovery.fetch("remote_main_before") == recovery.fetch("remote_main_after") &&
  recovery.fetch("remote_main_after") == provenance.fetch("remote_main"))

Dir.mktmpdir("kos-025-evidence-") do |directory|
  repository = File.join(directory, "observer")
  run("git", "clone", "-q", File.join(ARTIFACTS, "fixture-remote.bundle"), repository)
  main = git(repository, "rev-parse", "refs/heads/main").strip
  assert("bundle remote main", main == provenance.fetch("remote_main"))

  (1..3).each do |task_id|
    identity = review_identity(task_id)
    assert("task #{task_id} reviewed tip is remote", system("git", "merge-base", "--is-ancestor", identity.fetch(:tip), main,
      chdir: repository))
    commits = git(repository, "rev-list", "--reverse", "#{identity.fetch(:base)}..#{identity.fetch(:tip)}").lines.map(&:strip)
    assert("task #{task_id} nonempty reviewed range", !commits.empty?)
    commits.each do |commit|
      assert("task #{task_id} review lists #{commit}", identity.fetch(:markdown).include?(commit))
      message = git(repository, "show", "-s", "--format=%B", commit)
      trailers = message.lines(chomp: true).grep(/kos-task/i)
      assert("task #{task_id} #{commit} canonical trailer", trailers == [ "KOS-Task: #{task_id}" ])
    end
    expected_parent = identity.fetch(:base)
    commits.each do |commit|
      assert("task #{task_id} #{commit} linear parent",
        git(repository, "show", "-s", "--format=%P", commit).split == [ expected_parent ])
      expected_parent = commit
    end
    observed_trees = [ identity.fetch(:base), *commits ].map do |commit|
      git(repository, "show", "-s", "--format=%T", commit).strip
    end
    assert("task #{task_id} trees", observed_trees == identity.fetch(:trees))
    diff_options = [ "diff", "--binary", "--no-ext-diff", "--no-textconv" ]
    diff_options << "--full-index" unless task_id == 1
    diff = git(repository, *diff_options, identity.fetch(:base), identity.fetch(:tip))
    assert("task #{task_id} binary diff digest", Digest::SHA256.hexdigest(diff) == identity.fetch(:digest))
    paths = git(repository, "diff", "--name-only", "--no-ext-diff", "--no-textconv",
      identity.fetch(:base), identity.fetch(:tip)).lines.map(&:strip).sort
    assert("task #{task_id} changed paths", paths == identity.fetch(:paths))
  end

  assert("remote contains deliberate regression",
    git(repository, "show", "-s", "--format=%s", "4c77a16a4ece939cacdcd58852518b901a55b0d3").strip ==
      "Introduce greeting regression")
  bundled_check = run("bin/check", chdir: repository)
  assert("retained bundle fixture passes", bundled_check.lines.last&.strip ==
    "4 runs, 29 assertions, 0 failures, 0 errors, 0 skips")
end

fixture_log = File.read(File.join(ARTIFACTS, "fixture-check.txt"))
production_log = File.read(File.join(ARTIFACTS, "production-smoke.txt"))
check_log = File.read(File.join(ARTIFACTS, "kos-check.txt"))
assert("fixture checks passed", fixture_log.lines.last&.strip == "4 runs, 29 assertions, 0 failures, 0 errors, 0 skips")
assert("production smoke passed", production_log.lines.last&.strip == "5 runs, 216 assertions, 0 failures, 0 errors, 0 skips")
assert("candidate bin/check passed", check_log.lines.last&.strip == "283 runs, 4251 assertions, 0 failures, 0 errors, 0 skips")
assert("bundle verified", File.read(File.join(ARTIFACTS, "bundle-verification.txt")).include?("is okay"))
ready = artifact("ready.json")
assert("live server source identity", ready.fetch("status") == "ready" && ready.fetch("source_id") == provenance.fetch("source_id"))
