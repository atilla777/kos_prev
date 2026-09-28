# Add Plan Abandonment

## Goal

Provide one explicit, safe way to retire erroneous or obsolete started work so
non-expiring claims and incomplete blockers do not leave permanent live state.

## Scope

- Define minimal plan-level abandonment semantics for unfinished tasks.
- Preserve completed task results and immutable workflow history.
- Fence abandonment against stale observations and concurrent reports.
- Expose the operation through the API and thin CLI.
- Teach the orchestrator when abandonment requires explicit user intent.
- Keep abandoned work discoverable for inspection but never ready or claimable.

## Out Of Scope

- Automatic cancellation based on time or worker health.
- Deleting audit state or rewriting completed results.
- Per-step compensation or rollback of external repository effects.

## Acceptance Criteria

- An authorized caller can atomically abandon all unfinished work in one started
  plan using an explicit observed state fence.
- Concurrent claim, report, answer, takeover, and abandonment have one
  unambiguous winner and leave no partial plan state.
- Stale workers cannot report after successful abandonment.
- Abandoned tasks never satisfy dependencies or appear as ready work.
- Discovery distinguishes abandoned work from successfully completed work.
- API, CLI, concurrency, persistence, and orchestrator-contract tests pass.
- `bin/check` passes.
