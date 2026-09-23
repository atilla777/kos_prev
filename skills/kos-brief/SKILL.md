---
name: kos-brief
description: Use when the user invokes /kos-brief to create, resume, and schedule one built-in brief task by authoritative server state.
---

# KOS Brief Scheduler

Act only as the user-facing scheduler. Load `kos-cli`; never execute a workflow
step in the main agent. In particular, `brief` is now performed by a fresh
`kos-brief` profile because every step authority receives the task ID alone.

At command start, generate one cryptographically unpredictable owner ID such as
`kos-session-` followed by 32 lowercase hexadecimal digits for an exact resume.
Never read `KOS_OWNER_ID` or derive the owner from a PID, task, request,
timestamp, or project. New request-bound work gets its durable unique owner from
`kos-create`; after creation, retain the exact owner returned in authoritative
task context.

## Create Or Resume

Require one nonblank UTF-8 request, load `kos-create`, and delegate the complete
exact request and kind `brief`. Do not implement creation or inspect its intent,
lock, receipt, owner, definition, or CLI responses. Accept from `kos-create`
only one confirmed positive ASCII-decimal task ID, then retain only that ID.
Read authoritative context and, before any child dispatch, fence the completed
creation procedure's current owner. For `active`, use exact resume to the
scheduler's fresh owner with `--takeover-confirmed`; for an earlier invocation,
first require confirmation that its prior command process stopped. For
`blocked`, show the persisted reason and treat explicit reinvocation of the same
exact request as confirmation to recheck it, then exactly resume. For
`needs_human`, show the question and stop without treating request text as an
answer. Never dispatch while the task carries its durable creation owner or a
paused status.

Offer matching resumable brief work before delegating a new request. Repeat a
persisted `needs_human` question before resume, show a persisted `blocked`
reason, and require confirmation before active takeover. Selection, creation,
claim, resume, and ambiguous-response recovery use only `kos-cli`.

## Schedule

After obtaining the task ID, retain only its positive ASCII-decimal digits.
Repeatedly read authoritative task context and dispatch exactly one fresh child:

| Current step | Profile |
| --- | --- |
| `brief` | `kos-brief` |
| `review` | `kos-review` |
| `publish` | `kos-publish` |
| `verify` | `kos-verify` |

The child's complete prompt is only the task ID. It contains no request,
description, workflow, outcomes, tier, path, project ID, diff, Git state,
artifact, graph, owner, or claim version. Await the child, ignore its textual
response and claimed result, reread task context, and dispatch from the new
exact `current_step`.

At `publish`, a built-in context without the current `review_invalid` outcome
identifies an immutable pre-verification snapshot. Dispatch `kos-publish` only
to persist its migration block; it must not publish or materialize children.

Stop only when server status is `completed`, `needs_human`, or `blocked`. At a
pause, show the persisted server question or reason. The scheduler does not
read or validate Markdown or graph files, inspect Git, parse outcomes, report
attempts, validate or materialize children, or maintain step artifacts,
manifests, submission receipts, or pending submissions. Those operations belong
to the fresh step authority and server-fenced CLI protocol.
