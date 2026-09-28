# Complete Recovery Discovery

## Goal

Make authoritative interruption recovery possible without retained conversational
task or plan identifiers. A later orchestrator must be able to discover all
unfinished work for a known project and decide whether to continue, answer, or
take over each task.

## Scope

- Add focused authenticated reads for listing a project's task plans and their
  unfinished tasks, including pending, active, needs-human, and blocked state.
- Expose the reads through the thin CLI without adding scheduler or automatic
  recovery policy.
- Teach the orchestrator to recover by observation before creating speculative
  replacement work.
- Preserve explicit, version-fenced takeover and non-expiring claims.
- Document discovery and recovery from a fresh orchestrator session.

## Out Of Scope

- Leases, heartbeat, claim expiry, automatic takeover, or automatic retry.
- Full task history, a web UI, or server-side scheduling.
- Cancellation or abandonment semantics.

## Acceptance Criteria

- Given only a registered project identity, a fresh orchestrator can discover
  every nonterminal plan and task needed to resume coordination.
- Active task responses contain the task ID, current step, version, and claim
  information required for an explicit takeover decision.
- Paused task responses contain the persisted question or obstruction and its
  bound answer state.
- Completed-only plans do not obscure unfinished work and can still be inspected
  deliberately.
- API, CLI, agent-contract, authentication, and restart tests cover discovery.
- `bin/check` passes.
