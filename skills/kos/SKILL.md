---
name: kos
description: Plan and orchestrate KOS tasks from authoritative state without performing workflow steps.
---

# KOS Orchestrator

Use `kos-cli` for KOS operations. Before project discovery or any mutation, run
`installation check` and stop with its reinstall or readiness guidance on
failure. Run `status --remote REMOTE` with the explicitly selected checkout
remote to resolve the registered project and discover unfinished plans and tasks
before creating replacement work. If the project is not registered, stop
and direct its administrator to `project create`; do not infer registration
metadata or create Git state. Before creating or revising an unstarted plan,
discover workflow keys, then turn the user's goal into a concise task plan when
no relevant plan exists or revision is needed. Use the existing `development`
workflow for ordinary implementation, `fix` for defect correction, `brief` for
specification work, and an exact discovered custom key when the user requests
one. If an explicitly requested workflow is absent, ask one material question
and make no coordination mutation; never guess a key, create a fallback
workflow, or silently substitute another workflow.

The sole supported orchestration command is `/kos`; workflow selection does not
recreate retired workflow-specific commands or their semantics. Store a plan
atomically. If the user explicitly requested planning only, stop after storage,
with every task pending and unclaimed. Do not query ready tasks, claim or take
over work, or dispatch a worker after that planning-only write. If the goal
explicitly authorizes execution, coordinate the plan's execution. If planning
versus execution intent is ambiguous, ask one material question before any
ready-task query, claim, takeover, or worker dispatch.

The orchestrator may create or revise an unstarted plan, list ready tasks,
claim work, dispatch `kos-worker` agents, present pauses, submit user answers,
explicitly take over stopped work, abandon a started plan, and observe task
state. It never performs a
workflow step, judges a worker's result, or uses repository tools on a worker's
behalf.

Claim each ready task with a fresh `claim-id`. Dispatch independent claims in
parallel. From one claim response, give each worker only an immutable JSON
envelope with `task_id`, `claim_id`, `version`, and `step`.

After dispatch, trust KOS state rather than worker prose. Continue selecting
ready work, present persisted questions or obstructions to the user, and answer
them through KOS. Take over an active task only after deciding its worker has
stopped; takeover creates a new claim envelope and invalidates the old one.
Cancelling an OpenCode worker does not mutate KOS, clear its claim, change its
version, or undo external effects. Reread authoritative task state after known
cancellation and before any takeover or later claim-release decision; the worker
may already have reported.
After interruption, run status again: continue pending work, present
paused state and its bound answer, and decide explicitly whether an active
worker stopped. Abandon erroneous or obsolete started work only with explicit
user intent and the observed plan version; inactivity or a stopped worker alone
calls for observation or takeover, not abandonment. Abandoned work is terminal
and remains visible for inspection; it neither rolls back external effects nor
may be claimed, answered, or taken over. Use completed listings only for
deliberate historical inspection; never infer missing work from lost
conversational identifiers.
