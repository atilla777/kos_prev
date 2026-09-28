#!/usr/bin/env ruby

require "digest"
require "json"
require "open3"
require "tmpdir"

ARTIFACTS = File.expand_path(__dir__)

def artifact(name)
  JSON.parse(File.read(File.join(ARTIFACTS, name)))
end

def assert(label, condition)
  raise "FAIL #{label}" unless condition

  puts "PASS #{label}"
end

def run(*command, chdir: nil)
  output, error, status = Open3.capture3(*command, **(chdir ? { chdir: } : {}))
  raise "#{command.join(" ")} failed: #{error}" unless status.success?

  output
end

provenance = artifact("provenance.json")
discovery = artifact("cli-discovery.json")
observations = artifact("observations.json")
streams = artifact("stream-hashes.json").fetch("streams")
events = artifact("events.json").fetch("events")
lifecycle = artifact("lifecycle-evidence.json")
line_manifest = artifact("line-manifest.json").fetch("streams")
operator_events = artifact("operator-events.json").fetch("events").to_h do |entry|
  [ entry.fetch("name"), entry ]
end

source_id = provenance.fetch("candidate_source_id")
assert("valid candidate identity", source_id.match?(/\Asha256:[0-9a-f]{64}\z/) &&
  discovery.dig("installation", "source_id") == source_id &&
  discovery.dig("installation", "manifest_matches"))

expected_inventory = %w[
  agents/kos-worker.md
  commands/kos.md
  kos-installation.json
  skills/kos-cli/SKILL.md
  skills/kos-worker/SKILL.md
  skills/kos/SKILL.md
  skills/okf/SKILL.md
]
inventory = File.readlines(File.join(ARTIFACTS, "installed-inventory.txt"), chomp: true)
assert("minimal installed inventory", inventory == expected_inventory)

workflows = discovery.fetch("workflow_list_before_plan")
assert("built-in revision 3 catalog discovered", workflows.map { |entry| entry.fetch("key") }.sort ==
  %w[brief development fix] && workflows.all? { |entry| entry.fetch("revision") == 3 })
assert("workflow construction discoverable", discovery.dig("workflow_schema", "complete_valid_example") &&
  discovery.fetch("workflow_create_help_describes_input") &&
  discovery.fetch("plan_put_help_fields").sort ==
    %w[blocker_keys description_markdown key tasks title workflow_key].sort)
schema_output = operator_events.dig("workflow-schema", "output")
assert("installed schema and help retained", schema_output.dig("schema", "required_fields") == [ "steps" ] &&
  schema_output.dig("example", "steps", 0, "id") == "work" &&
  operator_events.dig("workflow-create-help", "output").include?("Input definition_json") &&
  operator_events.dig("workflow-create-help", "output").include?("Complete valid example") &&
  operator_events.dig("plan-put-help", "output").include?("description_markdown"))
assert("no source or fallback discovery", !discovery.fetch("source_inspection_used") &&
  !discovery.fetch("fallback_workflow_created"))

planning = observations.fetch("planning_only")
assert("planning-only stored one unstarted plan", planning.fetch("plan_version").zero? &&
  planning.fetch("tasks").length == 2 && planning.fetch("tasks").all? do |task|
    task.fetch("status") == "pending" && task.fetch("step") == "plan" &&
      task.fetch("version").zero? && !task.fetch("claimed")
  end)
assert("planning-only stopped before execution", !planning.fetch("ready_query_after_put") &&
  !planning.fetch("worker_launch_after_put") && planning.fetch("fixture_head") == planning.fetch("remote_main"))

release = observations.fetch("cancel_and_release")
assert("runtime cancellation preserved state", release.fetch("state_before_process_stop") ==
  release.fetch("state_after_process_stop"))
assert("exact release preserved step and advanced fences", release.dig("released", "status") == "pending" &&
  release.dig("released", "step") == release.dig("state_after_process_stop", "step") &&
  release.dig("released", "version") == release.dig("state_after_process_stop", "version") + 1 &&
  release.dig("released", "plan_version") == release.dig("state_after_process_stop", "plan_version") + 1 &&
  !release.dig("released", "claimed"))
assert("released worker became stale", release.fetch("late_report_error") == "conflict" &&
  release.fetch("state_unchanged_after_late_report"))

recovery = observations.fetch("fresh_recovery")
assert("fresh session used selected-remote status", !recovery.fetch("goal_contained_project_id") &&
  !recovery.fetch("goal_contained_plan_key") &&
  recovery.fetch("first_recovery_read") == "status --remote origin" &&
  recovery.fetch("same_plan_id") == planning.fetch("plan_id") && recovery.fetch("plan_count") == 1)
interrupted = recovery.fetch("interrupted").to_h { |task| [ task.fetch("task_id"), task ] }
takeovers = recovery.fetch("takeovers").to_h { |task| [ task.fetch("task_id"), task ] }
assert("active tasks were taken over with new fences", interrupted.keys.sort == [ 1, 2 ] &&
  takeovers.keys.sort == [ 1, 2 ] && interrupted.keys.all? do |task_id|
    before = interrupted.fetch(task_id)
    after = takeovers.fetch(task_id)
    after.fetch("version") == before.fetch("version") + 1 &&
      after.fetch("step") == before.fetch("step") &&
      after.fetch("claim_sha256") != before.fetch("claim_sha256")
  end)

results = observations.fetch("workflow_results").group_by { |entry| entry.fetch("task_id") }
assert("development workflows reached publication", results.keys.sort == [ 1, 2 ] &&
  results.values.all? do |entries|
    entries.map { |entry| [ entry.fetch("step"), entry.fetch("outcome") ] } == [
      [ "plan", "planned" ], [ "implement", "implemented" ],
      [ "review", "approved" ], [ "publish", "published" ]
    ]
  end)
final = observations.fetch("final")
assert("authoritative tasks completed", final.fetch("default_status_plan_count").zero? &&
  final.fetch("default_status_task_count").zero? &&
  final.fetch("tasks").all? { |task| task.fetch("status") == "completed" && !task.fetch("claimed") })

assert("raw stream commitments retained", streams.map { |stream| stream.fetch("name") }.sort ==
  %w[execution interrupted planning recovery] && streams.all? do |stream|
    stream.fetch("sha256").match?(/\A[0-9a-f]{64}\z/) &&
      stream.fetch("lines").positive? && stream.fetch("bytes").positive?
  end)

assert("sanitized events retain source commitments", events.all? do |entry|
  entry.fetch("raw_line_sha256").match?(/\A[0-9a-f]{64}\z/) &&
    %w[bash task].include?(entry.dig("event", "tool"))
end)
stream_index = streams.to_h { |entry| [ entry.fetch("name"), entry ] }
manifest_event_hashes = []
assert("line manifest covers every stream line", line_manifest.keys.sort == stream_index.keys.sort &&
  line_manifest.all? do |name, entries|
    entries.length == stream_index.dig(name, "lines") && entries.all? do |entry|
      valid = entry.fetch("raw_line_sha256").match?(/\A[0-9a-f]{64}\z/)
      if entry["retained_event"]
        valid && %w[bash task].include?(entry.fetch("tool")) && manifest_event_hashes << entry.fetch("raw_line_sha256")
      else
        valid && (!entry.key?("tool") || !%w[bash task].include?(entry.fetch("tool")))
      end
    end
  end)
assert("all executable events are retained", manifest_event_hashes.sort ==
  events.map { |entry| entry.fetch("raw_line_sha256") }.sort)
planning_events = events.select { |entry| entry.fetch("stream") == "planning" }
planning_commands = planning_events.filter_map { |entry| entry.dig("event", "state", "input", "command") }
workflow_index = planning_commands.index { |command| command.include?("workflow list") }
put_index = planning_commands.index { |command| command.include?("plan put --project-id") }
assert("planning event order", workflow_index && put_index && workflow_index < put_index &&
  planning_commands[(put_index + 1)..].none? { |command| command.match?(/task (ready|claim|takeover|release)/) } &&
  planning_events.none? { |entry| entry.dig("event", "tool") == "task" })
recovery_events = events.select { |entry| entry.fetch("stream") == "recovery" }
recovery_commands = recovery_events.filter_map { |entry| entry.dig("event", "state", "input", "command") }
assert("fresh recovery event order", recovery_commands.fetch(0).include?("installation check") &&
  recovery_commands.fetch(1).include?("status --remote origin") &&
  recovery_commands.count { |command| command.match?(/task takeover \d/) } == 2 &&
  recovery_commands.none? { |command| command.include?("plan put --project-id") })
worker_events = recovery_events.select { |entry| entry.dig("event", "tool") == "task" }
worker_descriptions = worker_events.map { |entry| entry.dig("event", "state", "input", "description") }
assert("recovery retained reviewed publication events", worker_descriptions.include?("Review Alpha changes") &&
  worker_descriptions.include?("Review Beta changes") && worker_descriptions.include?("Publish Alpha changes") &&
  worker_descriptions.include?("Publish Beta changes"))
assert("operator lifecycle evidence is bound", lifecycle.dig("process_stop", "before_status_sha256") ==
  lifecycle.dig("process_stop", "after_status_sha256") && lifecycle.dig("process_stop", "confirmed_exited") &&
  lifecycle.dig("release", "output", "status") == "pending" &&
  lifecycle.dig("late_report", "output", "error") == "conflict" &&
  lifecycle.dig("fresh_session_boundary", "interrupted_status_sha256") ==
    lifecycle.dig("fresh_session_boundary", "fresh_pre_session_status_sha256"))
assert("operator cancellation snapshots are exact", operator_events.dig("status-before-cancel", "output") ==
  operator_events.dig("status-after-cancel", "output") &&
  operator_events.dig("status-interrupted", "output") == operator_events.dig("status-fresh-before", "output"))
assert("operator release and stale report retained", operator_events.dig("release", "output", "task", "status") == "pending" &&
  operator_events.dig("release", "output", "task", "current_step") == "plan" &&
  operator_events.dig("release", "output", "task", "version") == 2 &&
  operator_events.dig("stale-report", "output", "error") == "conflict")
%w[1 2].each do |task_id|
  expected = { "plan" => "planned", "implement" => "implemented", "review" => "approved", "publish" => "published" }
  assert("task #{task_id} accepted workflow results retained", expected.all? do |step, outcome|
    operator_events.dig("task-#{task_id}-#{step}", "output", "outcome") == outcome
  end)
  assert("task #{task_id} publication observed", operator_events.dig("task-#{task_id}-publish", "output", "result")
    .match?(/ls-remote|Remote verification/))
end
assert("candidate check retained", File.read(File.join(ARTIFACTS, "kos-check.txt")).include?(
  "119 runs, 1878 assertions, 0 failures, 0 errors, 0 skips"))

retained_text = Dir[File.join(ARTIFACTS, "*")].select do |path|
  File.file?(path) && File.extname(path) != ".bundle" && File.basename(path) != "verify_evidence.rb"
end
  .map { |path| File.binread(path) }.join("\n")
assert("retained evidence excludes raw identities", !retained_text.match?(/kos-claim-[0-9a-f]+/) &&
  !retained_text.match?(/ses_[A-Za-z0-9]+/) && !retained_text.include?("KOS_API_TOKEN="))

Dir.mktmpdir("kos-040-evidence-") do |directory|
  observer = File.join(directory, "observer")
  run("git", "clone", "-q", File.join(ARTIFACTS, "fixture-remote.bundle"), observer)
  remote_main = run("git", "rev-parse", "refs/heads/main", chdir: observer).strip
  assert("bundle records independently observed remote", remote_main == provenance.fetch("fixture_remote_main") &&
    remote_main == final.fetch("remote_main"))
  assert("published commits are linear", run("git", "rev-list", "--reverse",
    "#{provenance.fetch("fixture_initial")}..#{remote_main}", chdir: observer).lines.map(&:strip) ==
      [ provenance.fetch("fixture_alpha"), remote_main ])
  assert("published commit messages", run("git", "show", "-s", "--format=%s",
    provenance.fetch("fixture_alpha"), chdir: observer).strip == "Add Alpha message" &&
    run("git", "show", "-s", "--format=%s", remote_main, chdir: observer).strip == "Add Beta message")
  paths = run("git", "diff", "--name-only", provenance.fetch("fixture_initial"), remote_main,
    chdir: observer).lines.map(&:strip).sort
  assert("published paths", paths == final.fetch("changed_paths").sort)
  diff = run("git", "diff", "--binary", "--no-ext-diff", "--no-textconv", "--full-index",
    provenance.fetch("fixture_initial"), remote_main, chdir: observer)
  assert("published diff identity", Digest::SHA256.hexdigest(diff) == provenance.fetch("fixture_diff_sha256"))
  check = run("bin/check", chdir: observer)
  assert("retained fixture passes", check.lines.last&.strip ==
    "3 runs, 3 assertions, 0 failures, 0 errors, 0 skips")
end

puts "task 040 evidence verified"
