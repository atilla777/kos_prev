#!/usr/bin/env ruby

require "digest"
require "json"

root = ARGV.fetch(0)
calls = []
main = []
scheduler = []
streams = []
main_steps = {
  "kos-brief" => { "task_id" => "1", "step" => "brief", "command" => "kos-brief.md" },
  "kos-custom" => { "task_id" => "4", "step" => "main_probe", "command" => "kos-task.md" },
  "kos-expired-recovery" => { "task_id" => "5", "step" => "main_probe", "command" => "kos-task.md" }
}

Dir.glob(File.join(root, "*.jsonl")).sort.each do |path|
  source = File.basename(path, ".jsonl")
  streams << {
    "source" => source,
    "sha256" => Digest::SHA256.file(path).hexdigest,
    "bytes" => File.size(path),
    "lines" => File.foreach(path).count
  }

  File.foreach(path) do |line|
    event = JSON.parse(line)
    part = event["part"]
    next unless part.is_a?(Hash) && part["type"] == "tool"

    state = part["state"]
    next unless state.is_a?(Hash) && state["status"] == "completed"

    if part["tool"] == "task"
      input = state.fetch("input")
      output = state["output"].to_s
      calls << {
        "source" => source,
        "timestamp" => event.fetch("timestamp"),
        "raw_line_sha256" => Digest::SHA256.hexdigest(line),
        "mode" => "subagent",
        "prompt" => input["prompt"],
        "profile" => input["subagent_type"],
        "model" => state.dig("metadata", "model", "modelID"),
        "result" => output.match?(/stale|rejected/i) ? "stale_rejected" : "reported"
      }
    elsif part["tool"] == "bash"
      command = state.dig("input", "command").to_s
      main_step = main_steps[source]
      if main_step && command.match?(/task report-attempt #{main_step.fetch("task_id")}\b/) &&
          command.include?("--step #{main_step.fetch("step")}")
        begin
          response = JSON.parse(state.fetch("output"))
          if response["task"].is_a?(Hash) && response.dig("task", "current_step") != main_step.fetch("step")
            command_source = File.expand_path("../../../.opencode/commands/#{main_step.fetch("command")}", __dir__)
            model = File.read(command_source)[/^model: [^\/]+\/(.+)$/, 1]
            main << {
              "source" => source,
              "timestamp" => event.fetch("timestamp"),
              "raw_line_sha256" => Digest::SHA256.hexdigest(line),
              "mode" => "main",
              "prompt" => main_step.fetch("task_id"),
              "profile" => "build",
              "model" => model,
              "step" => main_step.fetch("step"),
              "result" => "reported"
            }
          end
        rescue JSON::ParserError
          nil
        end
      end
      next unless command.match?(/task (?:show|resumable|resume)\b/)

      scheduler << {
        "source" => source,
        "timestamp" => event.fetch("timestamp"),
        "raw_line_sha256" => Digest::SHA256.hexdigest(line),
        "command" => command,
        "output" => state.fetch("output")
      }
    end
  end
end

puts JSON.pretty_generate({ "streams" => streams, "main" => main, "calls" => calls, "scheduler" => scheduler })
