---
name: kos
description: Shared scheduler for built-in and custom KOS commands, driven by authoritative server state.
---

# KOS Scheduler

Schedule one task in `development`, `fix`, `brief`, or `custom` mode. Load `kos-git` for
repository discovery and `kos-cli` for every public KOS operation. During
scheduling, do not access Rails, SQLite, the REST API, a task worktree, or task
Markdown.

Run `kos session-id` once to obtain this command's fresh canonical owner. Never
ask a model to generate randomness, read `KOS_OWNER_ID`, or reuse an owner.

## Select

Discover the invoking repository's canonical identity through `kos-git`, then
require its exact registered project through `kos-cli`.

- `development`: offer matching resumable work; otherwise use `task claim-next`
  for the `development` type. Never create a task.
- `fix` or `brief`: use `task create-or-get` with the mode, project, owner, and
  complete exact `$ARGUMENTS` expansion through standard input. Preserve every
  request byte; do not trim, infer argv, or interpret or unescape delimiters.
- `custom`: require one exact nonblank task-type key that is not `brief`,
  `development`, or `fix`. Offer resumable work with that exact key; otherwise
  use `task claim-next` with the same key. Never create a task. Preserve every
  key byte; do not trim, split, infer argv, or interpret or unescape delimiters.

Read authoritative context. Keep a completed or cancelled task terminal; otherwise use the
public claim or resume operations when needed to make the chosen task active for
this owner. Present persisted pause information and require the corresponding
human answer, confirmed resolution, or confirmed stopped-owner takeover before
resuming. Follow `kos-cli` whenever a mutation's result is ambiguous. Retain
only the resulting positive decimal task ID.

## Schedule

Repeat:

1. Read `task context` for the task ID.
2. Stop successfully on `completed` or `cancelled`. On `needs_human` or `blocked`, show the
   persisted question or reason and stop.
3. Require `active`. Before dispatch, if its server timestamp says the lease is
   expired, use `task resume` once for this invocation with the exact observed
   claim version and current step plus this command's owner, then reread context.
   Require the result to be active for that owner at the same step with claim
   version incremented by one and a renewed valid lease. Stop explicitly if
   that fenced recovery is rejected, ambiguous, unconfirmed, or would be needed
   a second time. A concurrently observed pause or terminal state also stops.
4. Snapshot the authoritative status, current step, claim version, and accepted
   artifact-index entry for that current step. Inspect only the current step's
   `execution_mode` and `model_tier` for execution selection. The command's
   frontmatter has already selected the main-agent model; `model_tier` selects a
   profile only for `subagent` execution. `/kos-task` uses the advanced command
   agent for every custom `main` step.
5. For `main`, load `kos-step` and execute exactly one step in this command
   agent. The step phase may read the task, evidence, and repository only as
   allowed by its authoritative workflow instruction.
6. For `subagent`, launch one fresh foreground `kos-step-standard` or
   `kos-step-advanced` child selected only by `model_tier`; its complete prompt
   is only the positive decimal task ID. Ignore its text and claimed result.
7. After either path, leave the step phase and reread context. Progress requires
   an authoritative change in status, current step, claim version, or the
   snapshotted current-step artifact-index entry. Continue from changed state.
   If state is unchanged while the lease remains valid, stop explicitly without
   launching another executor. If it is unchanged because the lease expired,
   perform the one exact resume above and dispatch that step at most once more.

Never infer execution behavior from a step ID or task type. During scheduling,
never add context to a child prompt, inspect artifact bodies or Git, interpret
child output, report a step, mutate a graph, or keep local recovery state.
Authoritative server state is the scheduler result.
