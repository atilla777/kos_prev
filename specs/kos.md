---
type: Product Specification
title: KOS task coordination
description: User-visible behavior of KOS task coordination and its three built-in scenarios.
tags:
  - kos
  - workflows
---

# Goal

KOS gives AI agents durable, authoritative task state and exclusive temporary
ownership while focused agents clarify requirements, implement, document,
review, publish, and verify work. A command can recover after interruption by
reading the task instead of reconstructing progress from local execution files.

# Actors

- A user requests product clarification, planned development, or a defect fix.
- A scheduler selects or creates one task and dispatches its current step.
- A fresh step agent performs and reports exactly one step within its authority.
- An administrator installs KOS and registers participating repositories.

# User Scenarios

- `/kos-brief <request>` creates or resumes a brief, specifies and independently
  reviews product behavior, publishes it, materializes the reviewed development
  graph, and independently verifies the published result.
- `/kos` resumes or claims the next available development task, then plans,
  implements and checks, documents, reviews, publishes, and verifies it.
- `/kos-fix <problem>` creates or resumes the exact reported problem, diagnoses
  it before planning, and follows the same checked, documented, reviewed,
  published, and verified delivery path.

# Rules

- Users choose a command and do not manage task type IDs, workflow IDs, project
  IDs, claims, leases, worktree paths, or internal outcomes.
- A command discovers its project from the invoking checkout's unambiguous
  `origin` and exact canonical `host/namespace/repository` registration, such as
  `github.com/atilla777/kos`. Database preparation installs the built-in catalog
  but never silently registers a repository.
- A task remains bound to the immutable workflow revision selected when it was
  created. Only one valid owner may advance it, and stale owners are fenced out.
- The scheduler only selects, creates, claims, or resumes work; reads
  authoritative state; dispatches one fresh agent for the exact current step;
  and reads state again. The dispatched input is only the positive task ID.
- A step agent reads its own authoritative context, fetches only needed accepted
  predecessor evidence, validates that evidence, executes one step, and reports
  its Markdown evidence and transition itself.
- KOS retains the last accepted Markdown artifact for each reported step.
  Repeating a step replaces that step's accepted artifact; KOS does not expose
  attempt history.
- A paused task retains the exact human question or technical reason. A human
  answer is durably bound to that pause before the same step is retried.
- Product behavior changes update the repository's `specs/` bundle before
  independent review. Technical-only work records why no product concept changed.
- Work remains uncommitted through implementation, documentation, and review.
  Publication is the only step that may commit or push.
- Publication does not complete a task. It advances to a fresh, independent,
  read-only verification step; only successful verification completes the task.
- Brief publication includes remote publication followed by atomic
  materialization of the reviewed child graph before verification.
- The server accepts built-in completion only from verification. A brief cannot
  advance past publication until its child graph exists, and an existing graph
  cannot be combined with a rewind to briefing or review.
- Incomplete blockers keep dependent tasks unavailable.
- Request-bound brief and fix creation derives one deterministic key from the
  exact command kind and request digest. The server returns the one exact task
  for that key even if its owner or lifecycle state has since changed, and
  rejects reuse with a different immutable definition.

# Errors

- A material product ambiguity pauses the current step with one precise question.
- A technical obstruction pauses the current step with its observed cause.
- Invalid transitions, stale claims, expired ownership, unavailable tasks,
  oversized or invalid artifacts, and contradictory child graphs fail explicitly
  without a partial state change.
- Missing project registration reports the canonical repository identity and the
  administrative registration action; KOS never substitutes another project.
- Discovery stops before task, worktree, or creation-recovery mutation when
  `origin` is absent or ambiguous, fetch and push identify different repositories,
  the canonical identity is invalid, or exact registration lookup fails.
- A step agent that cannot confirm its report leaves recovery to authoritative
  task observation; its textual response is never treated as a transition.

# Edge Cases

- After interruption or a lost response, commands observe authoritative task,
  Git, remote, or child-graph state as appropriate before retrying a mutation.
- A lost local creation receipt cannot duplicate a request-bound task because
  server-side scoped key uniqueness is the final creation boundary. Local
  intents and receipts remain separate from workflow-step artifacts.
- SSH and HTTPS remotes that unambiguously name the same host, namespace, and
  repository resolve to the same project. A different namespace is a different
  project.
- Renaming or transferring a repository updates the existing project
  registration so numeric identity, tasks, relationships, workflow snapshots,
  accepted evidence, and derived worktrees remain attached to it.
- Existing unfinished tasks upgraded to state-oriented execution retain their
  IDs, relationships, workflow, current step, status, and worktree, but begin
  with no accepted artifact index. If an immutable built-in snapshot predates
  verification, preserve its work, cancel it, and recreate it from the current
  catalog; it is not imported, dual-run, or repointed. Current snapshots may
  rerun their step to reconstruct evidence. Old local artifacts are not read.
- If the default branch moves before publication, implementation checks,
  documentation, and independent review repeat on the new base.
- A corrective outcome may move a task backward. The newly accepted artifact for
  a repeated step supersedes its prior accepted artifact.
- Brief-created children remain unavailable until their parent is verified and
  completed. The complete child graph is materialized atomically after remote
  publication and before verification.

# Acceptance Criteria

- A clean installation provides brief, development, and fix scenarios without
  hand-authored workflow JSON or numeric task type configuration.
- After explicit project registration, all commands discover the project from
  the checkout without project environment variables.
- Restart and lost-response recovery do not duplicate tasks, transitions, child
  graphs, commits, or pushes.
- Completed work exposes durable accepted Markdown evidence, required checks,
  independent review, one published commit, independent verification, completed
  status, and released ownership.
- Scheduler dispatch contains only the task ID; each fresh step agent obtains,
  validates, and reports its own authoritative state and evidence.
- Accepted artifact and transition changes are atomic and ownership-fenced.
- Paused questions, technical reasons, and exactly bound answers survive restart.
- Publication advances to verification, and no other outcome completes a
  built-in task.
- Automated acceptance proves lifecycle and installed-asset contracts. Separate
  live-model release evidence is required for all three real slash-command paths
  using isolated state and repositories; this specification does not claim that
  evidence has already been completed.

# Non-goals

KOS is not a general workflow engine, an autonomous requirements authority, a
code-review judge, a Git hosting service, a replacement for Git worktrees, or a
full attempt-history system. It does not assign one universal arbitrary state
document to every task, interpret accepted Markdown, or store product
specification files outside their repository.

Implementation boundaries are defined in
[Architecture Rules](../docs/architecture.md), and verification layers and
commands are defined in [Testing Rules](../docs/testing.md).
