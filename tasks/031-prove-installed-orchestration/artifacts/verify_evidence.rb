#!/usr/bin/env ruby

require "json"

root = __dir__
observations = JSON.parse(File.read(File.join(root, "observations.json")))
provenance = JSON.parse(File.read(File.join(root, "provenance.json")))
streams = JSON.parse(File.read(File.join(root, "stream-hashes.json"))).fetch("streams")

abort "missing source identity" unless provenance.fetch("candidate_source_id").match?(/\Asha256:[0-9a-f]{64}\z/)
abort "project discovery used an ID" unless observations.dig("project", "discovered_without_numeric_id")

tasks = observations.dig("plan", "tasks")
abort "wrong plan tasks" unless tasks.map { |task| task.fetch("key") } == %w[alpha color recovery]
abort "tasks were not independent" unless tasks.all? { |task| task.fetch("blocker_keys").empty? }

claims = observations.fetch("initial_claims")
abort "wrong initial claims" unless claims.map { |claim| claim.fetch("task_id") }.sort == [ 1, 2, 3 ]
abort "claims were not concurrent" unless claims.last.fetch("timestamp_ms") - claims.first.fetch("timestamp_ms") < 1_000

interrupted = observations.fetch("interrupted").to_h { |task| [ task.fetch("task_id"), task ] }
abort "missing durable question" unless interrupted.dig(2, "status") == "needs_human" &&
  interrupted.dig(2, "question") == "Which color should color.txt contain?"

takeovers = observations.dig("recovery", "takeovers").to_h { |task| [ task.fetch("task_id"), task ] }
[ 1, 3 ].each do |task_id|
  abort "missing takeover" unless takeovers.key?(task_id)
  abort "takeover reused claim" if interrupted.dig(task_id, "claim_sha256") == takeovers.dig(task_id, "claim_sha256")
end

abort "answer was not bound" unless observations.dig("recovery", "answer") == {
  "task_id" => 2, "step" => "work", "value" => "blue", "version" => 3
}

launches = observations.fetch("worker_launches")
abort "wrong worker launches" unless launches.map { |launch| launch.fetch("task_id") }.sort == [ 1, 2, 3 ] &&
  launches.all? { |launch| launch.fetch("profile") == "kos-worker" && launch.fetch("step") == "work" }

final_tasks = observations.fetch("final_tasks")
abort "tasks did not complete" unless final_tasks.length == 3 &&
  final_tasks.all? { |task| task.fetch("status") == "completed" }

files = observations.fetch("fixture_files")
abort "wrong fixture evidence" unless files.map { |file| file.fetch("path") }.sort ==
  %w[alpha.txt color.txt recovered.txt] && files.all? { |file| file.fetch("lines") == 1 }
abort "invalid stream evidence" unless streams.map { |stream| stream.fetch("name") }.sort == %w[first recovery] &&
  streams.all? { |stream| stream.fetch("sha256").match?(/\A[0-9a-f]{64}\z/) && stream.fetch("lines").positive? }

puts "task 031 evidence verified"
