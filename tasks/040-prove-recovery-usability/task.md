# Prove Recovery Usability

## Goal

Prove on a clean installed release that planning, workflow discovery,
interruption, release, and fresh-session recovery work without source inspection
or speculative global mutations.

## Scope

- Run a reproducible installed scenario in a separate published test repository.
- Exercise installation readiness, current-checkout project resolution, workflow
  listing and schema discovery, planning-only stop, later execution, worker
  cancellation, fenced release, fresh-session status, takeover, and completion.
- Verify built-in catalog presence and release identity before creating the plan.
- Record command/output evidence without secrets or mutable local database files.
- Convert every stable mechanical regression found by the run into an automated
  test before completion.

## Out Of Scope

- Semantic scoring of model output or a mandatory live-model CI gate.
- Leases, automatic stale-worker classification, or server-managed workers.
- Creating additional fallback workflows during acceptance.

## Acceptance Criteria

- The installed CLI discovers built-in workflows and explains custom workflow
  shape without reading KOS source.
- A planning-only request leaves an inspectable unstarted plan with no active
  claims, and execution begins only after an explicit later request.
- Cancelling one worker leaves observable state; exact release invalidates its
  report and makes the task safely pending.
- A fresh session resolves the checkout, obtains complete status, and resumes the
  existing plan without creating another one.
- The run completes through the intended reviewed workflow and records remote
  publication observation.
- `bin/check` and an independent evidence review pass.
