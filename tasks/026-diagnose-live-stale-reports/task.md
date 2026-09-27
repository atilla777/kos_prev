# Diagnose Live Stale Reports

## Goal

Eliminate repeated stale report submissions by live generic step agents while
preserving ownership fencing and bounded scheduler recovery.

## Source Evidence

- Task 025 retained four stale-report rejections across development, fix, and
  an expired-lease custom probe.
- Every rejection preserved authoritative state and every scheduler stopped
  without an automatic redispatch.
- Two built-in scenarios required confirmed-stopped continuation, and the
  isolated recovery probe was cancelled after two rejected standard steps.

## Scope

- Reproduce the live submission mismatch with sanitized evidence of the
  authoritative owner, claim version, step, and submitted fence.
- Determine whether the mismatch originates in context selection, retained
  model context, CLI invocation, workflow transition observation, or another
  boundary.
- Make the smallest correction that prevents an executor from reporting a
  stale predecessor fence during ordinary sequential execution.
- Preserve server-side rejection of genuinely stale owners, versions, leases,
  and steps plus the scheduler's unchanged-state stop.
- Repeat focused installed live scenarios sufficient to prove the correction.

## Out Of Scope

- Weakening claim fencing or accepting ambiguous reports.
- Combining workflow steps or changing Git publication behavior.
- Broad scheduler redesign.

## Acceptance Criteria

- A deterministic or retained live reproduction identifies the exact submitted
  field that differs from authoritative state.
- Ordinary sequential built-in and custom subagent reports use the current
  authoritative fence and advance without operator takeover.
- Genuine stale reports remain rejected without state change.
- Unchanged execution and expired-lease recovery remain bounded.
- Focused live evidence, `bin/check`, and relevant documentation pass.
