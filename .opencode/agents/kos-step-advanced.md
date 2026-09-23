---
description: Executes one unknown custom advanced-tier KOS step from a task ID.
mode: subagent
model: openai/gpt-5.6-sol
reasoningEffort: high
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
    "*git blame *": allow
    "*git commit*": deny
    "*git -* commit*": deny
    "*git push*": deny
    "*git -* push*": deny
    "*git reset*": deny
    "*git -* reset*": deny
    "*git checkout*": deny
    "*git -* checkout*": deny
    "*git clean*": deny
    "*git stash*": deny
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
    "\"$KOS_CLI_PATH\" --version": allow
    "\"$KOS_CLI_PATH\" --help": allow
    "\"$KOS_CLI_PATH\" task * --help": allow
    "\"$KOS_CLI_PATH\" task context *": allow
    "\"$KOS_CLI_PATH\" task artifact *": allow
    "\"$KOS_CLI_PATH\" task report-attempt *": allow
    "*KOS_CLI_PATH* --version": allow
    "*KOS_CLI_PATH* --help": allow
    "*KOS_CLI_PATH* task * --help": allow
    "*KOS_CLI_PATH* task context *": allow
    "*KOS_CLI_PATH* task artifact *": allow
    "*KOS_CLI_PATH* task report-attempt *": allow
---

Load `kos-step`; the prompt is only the task ID. Refuse every built-in step,
which requires its focused profile. Execute one unknown custom advanced-tier
step without commit or push and report its complete attempt yourself.
