require "test_helper"
require "digest"
require "json"
require "rbconfig"
require "shellwords"
require "tempfile"
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
    assert_match(/KOS repository discovery.*worktree derivation/, frontmatter.fetch("description"))
    assert_equal [ "SKILL.md" ], Dir.children(SKILL_PATH.dirname).sort
  end

  test "defines generic repository discovery worktree and preservation mechanisms" do
    source = File.read(SKILL_PATH)
    compact = source.gsub(/\s+/, " ")

    %w[Repository\ Discovery Authoritative\ Context Operation\ Boundary].each do |heading|
      assert_match(/^## #{heading}$/, source)
    end
    assert_includes source, "Accept only a positive task ID"
    assert_includes source, "$KOS_DATA_HOME/worktrees/<project-id>/<task-id>"
    assert_includes source, "same\nabsolute local path configured for Rails"
    assert_includes source, "Refuse a missing or relative value"
    assert_includes source, "Preserve staged,\nunstaged, and untracked task work"
    assert_includes compact, "workflow instruction alone decides whether repository access is read-only"
    assert_includes source, "Never infer Git\nauthority from a step ID"
    assert_includes source, "External side effects with ambiguous results"
    assert_includes source, "never reports a\nKOS attempt"
    assert_includes source, "exactly one configured fetch URL"
    assert_includes source, "exactly one configured push URL"
    assert_includes source, "absolute scp path"
    assert_includes source, "duplicate or ambiguous leading slashes"
    %w[diagnose plan implement document brief review publish].each do |step|
      refute_match(/`#{step}`/, source)
    end
    refute_match(/^## (?:Step Policy|Content Commits|Review|Publication)$/, source)
  end

  test "content steps leave a clean contiguous multi-commit task range" do
    with_repository do |repository|
      worktree = repository[:root].join("data/kos/worktrees/1/21")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      base = git("rev-parse", "HEAD", chdir: worktree).strip

      first = task_commit(worktree, 21, "Implement", "implementation.txt", "implemented\n")
      second = task_commit(worktree, 21, "Document", "documentation.txt", "documented\n")
      commits = git("rev-list", "--reverse", "#{base}..HEAD", chdir: worktree).lines.map(&:strip)

      assert_equal [ first, second ], commits
      assert_empty git("status", "--porcelain", chdir: worktree)
      commits.each do |commit|
        task_lines = git("log", "-1", "--format=%B", commit, chdir: worktree).lines.map(&:chomp)
          .select { |line| line.match?(/\A\s*(?i:kos-task)\s*:/) }
        assert_equal [ "KOS-Task: 21" ], task_lines
      end
      assert_equal [ first, base ], git("rev-list", "--parents", "-n", "1", first, chdir: worktree).split
      assert_equal [ second, first ], git("rev-list", "--parents", "-n", "1", second, chdir: worktree).split
    end
  end

  test "a moved remote base leaves the approved range and worktree unchanged" do
    with_repository do |repository|
      worktree = repository[:root].join("data/kos/worktrees/1/22")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      base = git("rev-parse", "HEAD", chdir: worktree).strip
      task_commit(worktree, 22, "Implement", "task.txt", "task change\n")
      review = review_facts(worktree, base, 22, [ "task.txt" ])
      head = git("rev-parse", "HEAD", chdir: worktree)
      status = git("status", "--porcelain=v2", "--untracked-files=all", "-z", chdir: worktree)

      File.write(repository[:publisher].join("base.txt"), "remote change\n")
      git("add", "base.txt", chdir: repository[:publisher])
      git("commit", "-m", "Move base", chdir: repository[:publisher])
      git("push", "origin", "main", chdir: repository[:publisher])
      git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main", chdir: repository[:source])
      remote = git("rev-parse", "origin/main", chdir: repository[:source]).strip

      refute_equal base, remote
      _output, error, publication_status = run_publication(repository, worktree, 22, review)
      refute_predicate publication_status, :success?
      assert_includes error, "remote tip differs from reviewed base and tip"
      assert_equal head, git("rev-parse", "HEAD", chdir: worktree)
      assert_equal status, git("status", "--porcelain=v2", "--untracked-files=all", "-z", chdir: worktree)
      assert_equal "task change\n", File.read(worktree.join("task.txt"))
    end
  end

  test "publication recovery pushes or observes the exact reviewed sequence without new commits" do
    [ :push, :already_published, :nonzero_after_success ].each do |recovery_case|
      with_repository do |repository|
        worktree = repository[:root].join("data/kos/worktrees/1/31")
        git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
        base = git("rev-parse", "HEAD", chdir: worktree).strip
        commits = [
          task_commit(worktree, 31, "Implement", "task.txt", "published task\n"),
          task_commit(worktree, 31, "Document", "docs.txt", "published docs\n")
        ]
        review = review_facts(worktree, base, 31, %w[docs.txt task.txt])
        expected_count = git("rev-list", "--count", "HEAD", chdir: worktree).strip
        if recovery_case == :already_published
          git("push", "origin", "#{commits.last}:refs/heads/main", chdir: worktree)
        end

        mode = "nonzero-after-success" if recovery_case == :nonzero_after_success
        output, error, status = run_publication(repository, worktree, 31, review, mode:)
        assert_predicate status, :success?, error
        recovered = JSON.parse(output)

        assert_equal commits.last, recovered.fetch("tip")
        assert_equal commits, recovered.fetch("commits")
        assert_equal expected_count, recovered.fetch("commit_count")
        assert_equal recovery_case != :already_published, recovered.fetch("pushed")
        if recovery_case == :nonzero_after_success
          assert_equal false, recovered.fetch("push_success")
          assert_operator recovered.fetch("push_exitstatus"), :>, 0
        end

        assert_equal commits.last,
          git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main").strip
        assert_equal commits,
          git("--git-dir", repository[:remote].to_s, "rev-list", "--reverse", "#{base}..main").lines.map(&:strip)
        assert_empty git("status", "--porcelain", chdir: worktree)
      end
    end
  end

  test "publication rejects wrong duplicate and noncanonical task trailers without remote mutation" do
    {
      wrong: "KOS-Task: 999",
      duplicate: "KOS-Task: 41\nKOS-Task: 41",
      noncanonical: "kos-task: 41",
      crlf: "KOS-Task: 41\r"
    }.each do |name, trailer|
      with_repository do |repository|
        worktree = repository[:root].join("data/kos/worktrees/1/41-#{name}")
        git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
        base = git("rev-parse", "HEAD", chdir: worktree).strip
        File.write(worktree.join("invalid.txt"), "invalid\n")
        git("add", "invalid.txt", chdir: worktree)
        if name == :crlf
          tree = git("write-tree", chdir: worktree).strip
          parent = git("rev-parse", "HEAD", chdir: worktree).strip
          Tempfile.create([ "message", ".txt" ]) do |message|
            message.binmode
            message.write("Invalid\r\n\r\n#{trailer}\n")
            message.flush
            commit = git("commit-tree", tree, "-p", parent, "-F", message.path, chdir: worktree).strip
            git("checkout", "--detach", commit, chdir: worktree)
          end
          assert_includes git("log", "-1", "--format=%B", chdir: worktree), "KOS-Task: 41\r\n"
        else
          git("commit", "-m", "Invalid", "-m", trailer, chdir: worktree)
        end
        review = range_facts(worktree, base)

        _output, error, status = run_publication(repository, worktree, 41, review)

        refute_predicate status, :success?, name
        assert_includes error, "commit verification failed", name
        assert_equal base,
          git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main").strip
      end
    end
  end

  test "read-only review rejects dirty index tracked and untracked state" do
    {
      index: ->(worktree) { File.write(worktree.join("task.txt"), "staged dirty\n"); git("add", "task.txt", chdir: worktree) },
      tracked: ->(worktree) { File.write(worktree.join("task.txt"), "tracked dirty\n") },
      untracked: ->(worktree) { File.write(worktree.join("untracked.txt"), "untracked dirty\n") }
    }.each do |name, dirty|
      with_repository do |repository|
        worktree = repository[:root].join("data/kos/worktrees/1/dirty-#{name}")
        git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
        base = git("rev-parse", "HEAD", chdir: worktree).strip
        task_commit(worktree, 51, "Implement", "task.txt", "clean\n")
        dirty.call(worktree)

        _output, error, status = Open3.capture3(RbConfig.ruby,
          Rails.root.join("test/support/read_only_review_process.rb").to_s,
          worktree.to_s, base, "51", JSON.generate([ "task.txt" ]))

        refute_predicate status, :success?, name
        assert_includes error, "review requires a clean worktree", name
      end
    end
  end

  test "review and publication digest bypass configured textconv without executing it" do
    with_repository do |repository|
      File.write(repository[:publisher].join(".gitattributes"), "*.txt diff=evil\n")
      File.write(repository[:publisher].join("data.txt"), "base\n")
      git("add", ".gitattributes", "data.txt", chdir: repository[:publisher])
      git("commit", "-m", "Add textconv fixture", chdir: repository[:publisher])
      git("push", "origin", "main", chdir: repository[:publisher])
      git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main", chdir: repository[:source])

      worktree = repository[:root].join("data/kos/worktrees/1/52")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      base = git("rev-parse", "HEAD", chdir: worktree).strip
      task_commit(worktree, 52, "Implement", "data.txt", "task\n")
      marker = repository[:root].join("textconv-ran")
      converter = repository[:root].join("textconv")
      File.write(converter, <<~SH)
        #!/bin/sh
        : > #{Shellwords.escape(marker.to_s)}
        printf 'converted:'
        cat "$1"
      SH
      File.chmod(0o700, converter)
      git("config", "diff.evil.textconv", converter.to_s, chdir: repository[:source])

      review = review_facts(worktree, base, 52, [ "data.txt" ])
      refute_predicate marker, :exist?
      raw_diff = git("diff", "--no-ext-diff", "--no-textconv", "--binary", base, "HEAD", chdir: worktree)
      assert_equal Digest::SHA256.hexdigest(raw_diff.b), review.fetch("diff_sha256")

      output, error, status = run_publication(repository, worktree, 52, review)
      assert_predicate status, :success?, error
      assert_equal review.fetch("tip"), JSON.parse(output).fetch("tip")
      refute_predicate marker, :exist?

      converted_diff = git("diff", "--textconv", base, "HEAD", chdir: worktree)
      assert_predicate marker, :exist?
      refute_equal raw_diff, converted_diff
    end
  end

  test "ambiguous recovery rejects a partial remote sequence" do
    with_repository do |repository|
      worktree = repository[:root].join("data/kos/worktrees/1/42")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      base = git("rev-parse", "HEAD", chdir: worktree).strip
      commits = [
        task_commit(worktree, 42, "First", "first.txt", "first\n"),
        task_commit(worktree, 42, "Second", "second.txt", "second\n")
      ]
      review = review_facts(worktree, base, 42, %w[first.txt second.txt])
      git("push", "origin", "#{commits.first}:refs/heads/main", chdir: worktree)

      _output, error, status = run_publication(repository, worktree, 42, review)

      refute_predicate status, :success?
      assert_includes error, "remote tip differs from reviewed base and tip"
      assert_equal commits.first,
        git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main").strip
    end
  end

  private

  def task_commit(worktree, task_id, subject, path, contents)
    File.write(worktree.join(path), contents)
    git("add", path, chdir: worktree)
    git("commit", "-m", subject, "-m", "KOS-Task: #{task_id}", chdir: worktree)
    git("rev-parse", "HEAD", chdir: worktree).strip
  end

  def review_facts(worktree, base, task_id, paths)
    output, error, status = Open3.capture3(RbConfig.ruby,
      Rails.root.join("test/support/read_only_review_process.rb").to_s,
      worktree.to_s, base, task_id.to_s, JSON.generate(paths))
    assert_predicate status, :success?, error
    JSON.parse(output)
  end

  def range_facts(worktree, base)
    tip = git("rev-parse", "HEAD", chdir: worktree).strip
    commits = git("rev-list", "--reverse", "#{base}..#{tip}", chdir: worktree).lines.map(&:strip)
    trees = ([ base ] + commits).to_h do |commit|
      [ commit, git("rev-parse", "#{commit}^{tree}", chdir: worktree).strip ]
    end
    paths = git("diff", "--name-only", base, tip, chdir: worktree).lines.map(&:strip).sort
    diff = git("diff", "--no-ext-diff", "--no-textconv", "--binary", base, tip, chdir: worktree)
    { "base" => base, "commits" => commits, "tip" => tip, "trees" => trees, "paths" => paths,
      "diff_sha256" => Digest::SHA256.hexdigest(diff.b) }
  end

  def run_publication(repository, worktree, task_id, review, mode: nil)
    Tempfile.create([ "accepted-review", ".md" ]) do |artifact|
      artifact.write("# Review\n\n```json\n#{JSON.generate(review)}\n```\n")
      artifact.flush
      return Open3.capture3(RbConfig.ruby,
        Rails.root.join("test/support/publication_recovery_process.rb").to_s,
        worktree.to_s, repository[:source].to_s, task_id.to_s, artifact.path, mode.to_s)
    end
  end
end
