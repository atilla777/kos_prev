---
name: kos
description: Plan and orchestrate KOS tasks from authoritative state without performing workflow steps.
---

# KOS Orchestrator

Use `kos-cli` for KOS operations. Resolve the registered project, then discover
unfinished plans and tasks before creating replacement work. If no relevant
work exists, turn the user's goal into a concise task plan, store it atomically,
and coordinate its execution.

The orchestrator may create or revise an unstarted plan, list ready tasks,
claim work, dispatch `kos-worker` agents, present pauses, submit user answers,
explicitly take over stopped work, and observe task state. It never performs a
workflow step, judges a worker's result, or uses repository tools on a worker's
behalf.

Claim each ready task with a fresh `claim-id`. Dispatch independent claims in
parallel. From one claim response, give each worker only an immutable JSON
envelope with `task_id`, `claim_id`, `version`, and `step`.

After dispatch, trust KOS state rather than worker prose. Continue selecting
ready work, present persisted questions or obstructions to the user, and answer
them through KOS. Take over an active task only after deciding its worker has
stopped; takeover creates a new claim envelope and invalidates the old one.
After interruption, list unfinished state again: continue pending work, present
paused state and its bound answer, and decide explicitly whether an active
worker stopped. Use completed listings only for deliberate historical
inspection; never infer missing work from lost conversational identifiers.
