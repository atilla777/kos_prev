# Add Repository Recovery Status

## Goal

Let an operator or fresh orchestrator resolve the registered project for the
current checkout and obtain its recoverable coordination state with one public
CLI operation.

## Scope

- Add a narrow local `project resolve` operation that reads an explicitly named
  Git remote, normalizes its URL with the existing repository identity rules,
  and performs the exact registered-project lookup.
- Add `status` for the current checkout that returns the resolved project plus
  its non-completed plans and tasks, including active claim fences, pauses,
  answers, dependencies, and workflow identity.
- Make remote selection explicit and deterministic; diagnose missing Git,
  checkout, remote, URL, registration, authentication, and transport failures.
- Keep the server authoritative and make status observational, with no claims,
  takeovers, plan creation, or inferred worker liveness.
- Document this local Git inspection as a focused CLI recovery exception rather
  than expanding KOS into repository or worktree management.

## Out Of Scope

- Choosing among multiple remotes automatically, cloning, worktrees, commits,
  branches, publication, or GitHub resource creation.
- Automatic stale-worker detection, takeover, release, or scheduling.
- A new persisted aggregate status model.

## Acceptance Criteria

- From a checkout with a configured supported remote, `project resolve` returns
  the same registered project as exact canonical identity lookup.
- `status` returns all default non-completed recovery state needed to decide
  whether to continue, answer, take over, or release work.
- The caller can explicitly select the remote; absent or ambiguous local state
  fails without a server mutation.
- Status does not classify an active claim as stale or perform lifecycle writes.
- Tests isolate Git configuration and cover supported URL forms, missing and
  malformed remotes, absent registration, transport failure, and successful
  recovery output.
- Product and architecture documents identify the narrow exception, and
  `bin/check` passes.
