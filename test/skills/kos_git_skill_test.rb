require "test_helper"
require "yaml"

class KosGitSkillTest < ActiveSupport::TestCase
  include GitRepositoryHelpers

  SKILL_PATH = Rails.root.join("skills/kos-git/SKILL.md")

  test "is a discoverable distributable OpenCode skill" do
    source = File.read(SKILL_PATH)
    match = source.match(/\A---\n(.*?)\n---/m)

    assert match
    frontmatter = YAML.safe_load(match[1])
    assert_equal "kos-git", frontmatter.fetch("name")
    assert_match(/KOS task worktree derivation/, frontmatter.fetch("description"))
    assert_equal [ "SKILL.md" ], Dir.children(SKILL_PATH.dirname).sort
  end

  test "derives Git state by task ID and centralizes step authority" do
    source = File.read(SKILL_PATH)

    [
      "Repository Discovery", "Authoritative Context", "Step Policy", "Publication", "Independent Verification"
    ].each { |heading| assert_match(/^## #{Regexp.escape(heading)}$/, source) }

    assert_includes source, "Accept only a positive task ID"
    assert_includes source, "derive the project ID,\nregistered identity, remote, default branch"
    assert_includes source, "Never accept paths, commands, a diff, changed\nfiles, project identity, or Git facts from the dispatcher"
    assert_includes source, "<kos-data-home>/worktrees/<project-id>/<task-id>"
    assert_includes source, "KOS-Task: <task-id>"
    assert_includes source, "`publish` alone may update a moved base, stage, commit, and push"
    assert_includes source, "`implement` and `document` may mutate"
    assert_includes source, "`diagnose`, `plan`, `review`, and `verify` are read-only"
    assert_includes source, "At `verify`, perform no mutation"
    assert_includes source, "Independently fetch the remote branch"
    assert_includes source, "`KOS-Task: <task-id>` trailer"
    assert_includes source, "changed paths and patch"
    assert_includes source, "`materialization_missing`"
    assert_includes source, "never reports a KOS\nattempt"
    assert_includes source, "exactly one configured fetch URL"
    assert_includes source, "exactly one configured push URL"
    assert_includes source, "absolute scp path"
    assert_includes source, "duplicate or ambiguous leading slashes"
    assert_includes source, "Fetch and push spellings may\ndiffer only when both normalize to the same identity"
    assert_includes source, "Before a task ID exists, a scheduler or `kos-create` returns that canonical\nidentity to `kos-cli` for exact project lookup"
    assert_includes source, "compare the discovered identity directly with the registered identity in `task\ncontext`; do not call `project show`"
    assert_match(/stops before task or local recovery\s+mutation/, source)
  end

  test "separate task worktrees preserve independent uncommitted changes without commits" do
    with_repository do |repository|
      first = repository[:root].join("data/kos/worktrees/1/11")
      second = repository[:root].join("data/kos/worktrees/1/12")
      base = git("rev-parse", "origin/main", chdir: repository[:source]).strip

      git("worktree", "add", "--detach", first.to_s, "origin/main", chdir: repository[:source])
      git("worktree", "add", "--detach", second.to_s, "origin/main", chdir: repository[:source])
      File.write(first.join("first.txt"), "first task\n")
      File.write(second.join("second.txt"), "second task\n")

      assert_equal base, git("rev-parse", "HEAD", chdir: first).strip
      assert_equal base, git("rev-parse", "HEAD", chdir: second).strip
      assert_includes git("status", "--porcelain", chdir: first), "first.txt"
      refute_includes git("status", "--porcelain", chdir: first), "second.txt"
      assert_includes git("status", "--porcelain", chdir: second), "second.txt"
      refute_includes git("status", "--porcelain", chdir: second), "first.txt"
      assert_equal "1", git("rev-list", "--count", "HEAD", chdir: first).strip
      assert_equal "1", git("rev-list", "--count", "HEAD", chdir: second).strip
    end
  end

  test "a moved base keeps compatible task work uncommitted" do
    with_repository do |repository|
      worktree = repository[:root].join("data/kos/worktrees/1/21")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      File.write(worktree.join("task.txt"), "task change\n")

      File.write(repository[:publisher].join("base.txt"), "remote change\n")
      git("add", "base.txt", chdir: repository[:publisher])
      git("commit", "-m", "Move base", chdir: repository[:publisher])
      git("push", "origin", "main", chdir: repository[:publisher])
      git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main", chdir: repository[:source])
      remote_head = git("rev-parse", "origin/main", chdir: repository[:source]).strip

      git("checkout", "--merge", "--detach", remote_head, chdir: worktree)

      assert_equal remote_head, git("rev-parse", "HEAD", chdir: worktree).strip
      assert_equal "task change\n", File.read(worktree.join("task.txt"))
      assert_includes git("status", "--porcelain", chdir: worktree), "task.txt"
      assert_equal "2", git("rev-list", "--count", "HEAD", chdir: worktree).strip
    end
  end

  test "publication recovery observes the existing remote commit without creating another" do
    with_repository do |repository|
      worktree = repository[:root].join("data/kos/worktrees/1/31")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      File.write(worktree.join("task.txt"), "published task\n")
      git("add", "task.txt", chdir: worktree)
      git("commit", "-m", "KOS task 31: Publish", "-m", "KOS-Task: 31", chdir: worktree)
      candidate = git("rev-parse", "HEAD", chdir: worktree).strip

      git("push", "--porcelain", "origin", "#{candidate}:refs/heads/main", chdir: worktree)
      commit_count = git("rev-list", "--count", "HEAD", chdir: worktree)
      remote_before_recovery = git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main")

      # A restarted publication observes first and must not commit or push again.
      git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main", chdir: repository[:source])
      observed = git("rev-parse", "origin/main", chdir: repository[:source]).strip
      published = git_success?("merge-base", "--is-ancestor", candidate, observed, chdir: worktree)

      assert_equal candidate, observed
      assert published
      assert_equal commit_count, git("rev-list", "--count", "HEAD", chdir: worktree)
      assert_empty git("status", "--porcelain", chdir: worktree)
      assert_equal "31", git("log", "-1", "--format=%(trailers:key=KOS-Task,valueonly)", chdir: worktree).strip
      assert_equal remote_before_recovery,
        git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main")
    end
  end

  test "rewritten remote history blocks base movement without changing task state" do
    with_repository do |repository|
      worktree = repository[:root].join("data/kos/worktrees/1/41")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      previous_base = git("rev-parse", "HEAD", chdir: worktree).strip
      File.write(worktree.join("task.txt"), "preserve me\n")

      git("checkout", "--orphan", "replacement", chdir: repository[:publisher])
      git("rm", "-rf", ".", chdir: repository[:publisher])
      File.write(repository[:publisher].join("replacement.txt"), "rewritten\n")
      git("add", "replacement.txt", chdir: repository[:publisher])
      git("commit", "-m", "Rewrite history", chdir: repository[:publisher])
      git("push", "--force", "origin", "replacement:main", chdir: repository[:publisher])
      git("fetch", "--no-tags", "--force", "origin", "refs/heads/main:refs/remotes/origin/main",
        chdir: repository[:source])
      rewritten_base = git("rev-parse", "origin/main", chdir: repository[:source]).strip

      refute git_success?("merge-base", "--is-ancestor", previous_base, rewritten_base, chdir: worktree)
      assert_equal previous_base, git("rev-parse", "HEAD", chdir: worktree).strip
      assert_equal "preserve me\n", File.read(worktree.join("task.txt"))
      assert_includes git("status", "--porcelain", chdir: worktree), "task.txt"
    end
  end

  test "reuse detects a local pre-publication commit and preserves it for inspection" do
    with_repository do |repository|
      worktree = repository[:root].join("data/kos/worktrees/1/51")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      fetched_base = git("rev-parse", "origin/main", chdir: repository[:source]).strip
      File.write(worktree.join("unexpected.txt"), "unexpected commit\n")
      git("add", "unexpected.txt", chdir: worktree)
      git("commit", "-m", "Unexpected commit", chdir: worktree)
      unexpected_head = git("rev-parse", "HEAD", chdir: worktree).strip

      refute git_success?("merge-base", "--is-ancestor", unexpected_head, fetched_base, chdir: worktree)
      assert git_success?("merge-base", "--is-ancestor", fetched_base, unexpected_head, chdir: worktree)
      assert_equal unexpected_head, git("rev-parse", "HEAD", chdir: worktree).strip
      assert File.exist?(worktree.join("unexpected.txt"))
    end
  end

  test "candidate observations reject a matching trailer with the wrong subject and paths" do
    with_repository do |repository|
      worktree = repository[:root].join("data/kos/worktrees/1/61")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      remote_before = git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main").strip
      File.write(worktree.join("unrelated.txt"), "not reviewed\n")
      git("add", "unrelated.txt", chdir: worktree)
      git("commit", "-m", "Wrong subject", "-m", "KOS-Task: 61", chdir: worktree)

      subject = git("log", "-1", "--format=%s", chdir: worktree).strip
      paths = git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD", chdir: worktree).lines.map(&:strip)
      trailer = git("log", "-1", "--format=%(trailers:key=KOS-Task,valueonly)", chdir: worktree).strip

      assert_equal "61", trailer
      refute_equal "KOS task 61: Expected", subject
      refute_equal [ "expected.txt" ], paths
      assert_equal remote_before,
        git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main").strip
    end
  end
end
