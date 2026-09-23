---
description: Executes the only commit-and-push KOS publish step from a task ID.
mode: subagent
model: openai/gpt-5.6-terra
reasoningEffort: medium
permission:
  task: deny
  skill:
    "*": deny
    kos-step: allow
    kos-cli: allow
    kos-git: allow
  external_directory: allow
  bash:
    "*": ask
    "*git remote get-url *": allow
    "*git rev-parse *": allow
    "*git status *": allow
    "*git diff *": allow
    "*git log *": allow
    "*git show *": allow
    "*git merge-base *": allow
    "*git worktree list*": allow
    "*git worktree add *": allow
    "*git fetch *": allow
    "*git config --get *": allow
    "*git symbolic-ref *": allow
    "*git rev-list *": allow
    "*git cat-file *": allow
    "*git ls-tree *": allow
    "*git ls-remote *": allow
    "*git diff-tree *": allow
    "*git for-each-ref *": allow
    "*git branch --show-current*": allow
    "*git apply *": allow
    "*kos *": deny
    "*bin/kos *": deny
    "*curl *": deny
    "*sqlite3 *": deny
    "*rails *": deny
    "test *KOS_CLI_PATH*": allow
    "test *KOS_DATA_HOME*": allow
    "test *": allow
    "[ *KOS_CLI_PATH*": allow
    "date -u *": allow
    "pwd": allow
    "ls -ld *": allow
    "ls *": allow
    "stat *": allow
    "readlink *": allow
    "realpath *": allow
    "printenv KOS_CLI_PATH": allow
    "printenv KOS_DATA_HOME": allow
    "printenv XDG_DATA_HOME": allow
    "printenv HOME": allow
    "printf *KOS_CLI_PATH*": allow
    "*git *add*": allow
    "git commit -F *": allow
    "git push origin HEAD:refs/heads/*": allow
    "git commit *--amend*": deny
    "git commit -F * *": deny
    "git push --force *": deny
    "git push -f *": deny
    "git push --delete *": deny
    "git push --mirror *": deny
    "git push --all *": deny
    "git push origin +*": deny
    "git push origin HEAD:refs/heads/* *": deny
    "*git *reset*": deny
    "*git *clean*": deny
    "*git *checkout*": deny
    "*git *restore*": deny
    "*git *switch*": deny
    "*git *config --global*": deny
    "*git *config --system*": deny
    "*git *worktree remove*": deny
    "*git *worktree prune*": deny
    "*git *branch -D*": deny
    "*git *update-ref*": deny
    "git checkout --merge --detach *": allow
    "git checkout --merge --detach * *": deny
    "\"$KOS_CLI_PATH\" --version": allow
    "\"$KOS_CLI_PATH\" --help": allow
    "\"$KOS_CLI_PATH\" task * --help": allow
    "\"$KOS_CLI_PATH\" task context *": allow
    "\"$KOS_CLI_PATH\" task artifact *": allow
    "\"$KOS_CLI_PATH\" task children *": allow
    "\"$KOS_CLI_PATH\" task validate-children *": allow
    "\"$KOS_CLI_PATH\" task materialize-children *": allow
    "\"$KOS_CLI_PATH\" task report-attempt *": allow
    "*KOS_CLI_PATH* --version": allow
    "*KOS_CLI_PATH* --help": allow
    "*KOS_CLI_PATH* task * --help": allow
    "*KOS_CLI_PATH* task context *": allow
    "*KOS_CLI_PATH* task artifact *": allow
    "*KOS_CLI_PATH* task children *": allow
    "*KOS_CLI_PATH* task validate-children *": allow
    "*KOS_CLI_PATH* task materialize-children *": allow
    "*KOS_CLI_PATH* task report-attempt *": allow
    "*;*": deny
    "*&&*": deny
    "*||*": deny
    "*|*": deny
---

Load `kos-step`; the prompt is only the task ID. Require exact current step
`publish`. Before Git, worktree, validation, or child-graph side effects, reject
a built-in context whose outcomes omit `review_invalid` as an immutable
pre-verification snapshot. Report `blocked` with the migration reason: preserve
the work, cancel the unfinished task, and recreate it from the current catalog;
never publish, materialize, import, or repoint it. Otherwise validate accepted review evidence and use `review_invalid` when it is
not publishable. Load `kos-git`; this profile alone may update a moved base,
commit, and push. For brief tasks, validate the accepted graph before commit and
materialize its exact children only after remote publication is observed. Use
`graph_invalid` before publication and `blocked` for an unsafe post-publication
conflict. Report `published` only after all required side effects are observed,
then report the complete attempt yourself.
