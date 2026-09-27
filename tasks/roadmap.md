# KOS Development Roadmap

This is the authoritative ordered list for development of KOS itself. Detailed
scope and progress live in each linked task directory. Task files are repository
development records and are not read by the KOS server or CLI.

## Completed

| ID | Task | Status | Dependencies |
| --- | --- | --- | --- |
| 001 | [Bootstrap the file workflow](001-bootstrap-file-workflow/task.md) | done | - |
| 002 | [Establish the server and CLI baseline](002-server-cli-baseline/task.md) | done | 001 |
| 003 | [Remove OpenCode permission policy](003-remove-opencode-permissions/task.md) | done | 002 |
| 004 | [Simplify request-bound task creation](004-simplify-task-creation/task.md) | done | 002 |
| 005 | [Rewrite the CLI skill](005-rewrite-cli-skill/task.md) | done | 004 |
| 006 | [Rewrite schedulers and commands](006-rewrite-schedulers-and-commands/task.md) | done | 003, 005 |
| 007 | [Simplify step agents](007-simplify-step-agents/task.md) | done | 006 |
| 008 | [Simplify Git publication](008-simplify-git-publication/task.md) | done | 007 |
| 009 | [Run live acceptance scenarios](009-live-acceptance/task.md) | done | 008 |
| 010 | [Prevent publication without required checks](010-enforce-check-evidence/task.md) | done | 009 |
| 011 | [Complete built-in tasks at publication](011-terminal-publication/task.md) | done | 010 |
| 012 | [Materialize brief graphs atomically](012-atomic-brief-materialization/task.md) | done | 011 |
| 013 | [Publish reviewed commit sequences](013-reviewed-commit-ranges/task.md) | done | 011, 012 |
| 014 | [Run simplified live acceptance](014-simplified-live-acceptance/task.md) | done | 011, 012, 013 |
| 015 | [Preserve exact slash-command arguments](015-preserve-slash-command-arguments/task.md) | done | 014 |
| 016 | [Record post-acceptance decisions](016-record-observation-decisions/task.md) | done | 015 |
| 017 | [Make workflow execution generic](017-generic-workflow-execution/task.md) | done | 016 |
| 018 | [Restore production boot](018-restore-production-boot/task.md) | done | 017 |

## Planned

The ordered remediation backlog below comes from the 2026-09-26 readiness
review retained at
[`tasks/018-restore-production-boot/artifacts/readiness-review-2026-09-26.md`](018-restore-production-boot/artifacts/readiness-review-2026-09-26.md).
Each task preserves its own stable scope, plan, status, source evidence, and
acceptance criteria so a new session can continue from the first unblocked row.

| ID | Task | Status | Dependencies |
| --- | --- | --- | --- |
| 019 | [Bound scheduler recovery](019-bound-scheduler-recovery/task.md) | planned | 018 |
| 020 | [Harden brief graphs](020-harden-brief-graphs/task.md) | planned | 019 |
| 021 | [Resolve custom workflow execution](021-resolve-custom-execution/task.md) | planned | 020 |
| 022 | [Tighten runtime boundaries](022-tighten-runtime-boundaries/task.md) | planned | 021 |
| 023 | [Test real scheduling](023-test-real-scheduling/task.md) | planned | 022 |
| 024 | [Complete production operations](024-complete-operations/task.md) | planned | 023 |
| 025 | [Run current live acceptance](025-current-live-acceptance/task.md) | planned | 024 |

## Resolved Decisions

### Server Workflow And Data Model

Retain the current workflow and five-table data model. The live acceptance runs
used or validated request idempotence, ownership fencing, pause and answer
binding, required-check gates, interruption recovery, immutable workflow
snapshots, and atomic brief graph materialization. Their extra agent launches do
not identify redundant server state.

Reconsider a focused reduction only when ordinary sessions show one of these
conditions:

- `document` is repeatedly a no-op and combining it with implementation would
  not weaken product-specification maintenance;
- agents make incorrect decisions from later accepted artifacts retained after
  a backward transition;
- leases or claim fencing repeatedly require operator intervention without
  preventing stale or concurrent writes;
- authoritative current state plus external session evidence cannot diagnose or
  recover multiple failures; or
- an explicit product decision removes support for custom workflows and task
  types.

### Git Publication

Retain agent-driven publication. The live acceptance runs observed six correct
remote publications, including a reviewed multi-commit sequence and recovery
after an interrupted publisher, without a reproduced Git correctness failure.

Reconsider a narrow deterministic Git helper after either:

- one unsafe result, such as a wrong range or ref update, duplicate push, or an
  accepted `published` result without the reviewed remote range;
- two Git-specific retries or manual interventions caused by ambiguous remote
  classification or recovery; or
- measured publisher cost becomes operationally significant.

If triggered, prefer a local helper limited to validating the reviewed range,
fetching, classifying, pushing without force, and observing the remote result.
Keep Git state outside Rails, and leave brief graph materialization and fenced
task reporting separate rather than implying a cross-system transaction.
