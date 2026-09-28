# Add Fenced Claim Release

## Goal

Allow a caller that knows an active worker has stopped to return that one task
to pending safely without immediately dispatching a replacement or abandoning
the entire plan.

## Scope

- Add `task release` as an explicit lifecycle mutation requiring the active
  `claim_id`, observed task `version`, and current `step`.
- Atomically clear the matching claim, return the same step to pending, and
  advance both task and aggregate plan versions.
- Reject stale, mismatched, paused, completed, abandoned, or unclaimed releases
  without changing state.
- Keep takeover as the direct replacement operation and release as the operation
  for intentional stop without immediate redispatch.
- Teach the orchestrator to reread after known worker cancellation and release
  only when it owns the exact cancelled dispatch envelope.
- Preserve non-expiring claims and exclude server-clock or health-based release.

## Out Of Scope

- Leases, heartbeat, expiry, automatic stale-worker detection, or automatic
  cancellation hooks in OpenCode.
- Releasing another unknown worker based only on age or inactivity.
- Rolling back repository or other external effects of the stopped worker.

## Acceptance Criteria

- An exact active claim can be released once and becomes dependency-eligible
  pending work at the same workflow step.
- Release advances task and plan versions and invalidates every later report
  from the released worker.
- Concurrent release versus report, takeover, or plan abandonment has one winner
  and leaves no partial state.
- A stale or mismatched release changes neither task nor plan state.
- CLI help and orchestrator guidance distinguish release, takeover, pause, and
  abandonment.
- Model, API, CLI, concurrency, persistence, and skill tests cover release, and
  `bin/check` passes.
