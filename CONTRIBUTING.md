# Contributing

## Workflow

1. Work on one agreed task with explicit scope and acceptance criteria.
2. Read `specs/index.md`, the product specification, architecture rules, testing
   rules, and installation contract before changing behavior or boundaries.
3. Make the smallest change that satisfies the current task.
4. Update tests and synchronize product and technical documentation.
5. Run `bin/check` before publication.
6. Commit only at the publication stage, push without force, and verify the
   remote result independently before completing the task.

After scope approval, continue through implementation, verification, commit,
push, remote observation, and task-state update unless a product decision or
technical blocker requires the user.

## Change Rules

- Do not implement later roadmap items opportunistically or add compatibility
  paths without a concrete persisted or shipped requirement.
- Do not commit secrets, local SQLite files, logs, temporary files, creation
  intents or receipts, legacy task artifacts, or worktrees.
- Agent tooling uses the public CLI, never direct HTTP, Rails, or SQLite.
- Keep scheduler logic state-oriented: after selection it dispatches only a task
  ID, never artifact, description, Git, checks, outcomes, or pending reports.
- Keep step logic self-contained: read focused context and required accepted
  artifacts, validate predecessors, execute one step, and atomically report its
  own artifact and transition.
- Do not add local `tasks/<id>/<step>.md`, answer sidecars, report receipts,
  pending submissions, attempt history, or dual-read fallback.
- Keep request-bound creation intents and receipts separate from step artifacts;
  every create-and-claim retry must reuse its deterministic server creation key.
- Preserve exact claim-version and step fencing for resume and reporting. Keep
  artifact acceptance and transition in one transaction.
- Keep diagnosis, planning, review, and verification read-only. Keep all work
  uncommitted until publication; publication alone may commit, push, and
  materialize a brief graph.
- Publication advances to fresh independent verification. Only `verified` may
  complete a built-in task.
- Preserve canonical repository discovery and exact registration; do not add
  `KOS_PROJECT_*` configuration or infer projects by numeric ID in user flows.
- Keep user-facing commands and normative documents in English unless a task
  explicitly establishes another convention.

## Review

Review prioritizes correctness, transaction and fencing invariants, behavioral
regressions, security, state-oriented recovery, profile authority, migration
safety, and missing tests. KOS workflow review and post-publication verification
must be fresh, independent, and read-only.
