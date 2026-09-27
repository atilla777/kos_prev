---
name: kos-cli
description: Use for discovering and safely invoking the public KOS CLI, interpreting its results, and recovering ambiguous operations.
---

# KOS CLI

## Role And Configuration

Use only the executable at the absolute administrator-configured
`KOS_CLI_PATH`. Do not substitute an ambient `kos`, repository executable,
direct HTTP request, Rails command, or SQLite access. Stop as `blocked` when the
configured executable is unavailable or incompatible.

`KOS_API_URL` selects the server and otherwise defaults to the CLI's local URL.
`KOS_API_TOKEN` is required for server-backed operations except `health`;
`session-id` is local and needs neither setting. Never print the token, put it in
process arguments, or embed it in a URL. It is a shared bearer credential whose
holders are fully trusted for every application operation; owner IDs, leases,
and claim-version fences provide concurrency consistency, not authorization.

## Discover And Invoke

Run `--version` and top-level `--help` to identify the installed CLI. The common
templates below may be used directly. Installed per-command help is the fallback
for uncommon operations and compatibility diagnosis; a missing required
operation is `blocked`, not permission to emulate it through another interface.

Pass every value as a distinct process argument. Never interpolate task text,
Markdown, JSON, paths, identifiers, or credentials into shell syntax. Where
help permits `-` as a file value, prefer standard input for exact structured
content. Never use a repository-local task artifact, sidecar, or receipt as KOS
protocol state.

## Common Templates

Each bracketed value below is one separate process argument. Supply file value
`-` content on standard input, never through shell interpolation.

- Owner: `session-id`.
- Project lookup: `project show --repository-identity [IDENTITY]`.
- Request creation: `task create-or-get --project-id [ID] --kind [KIND] --owner-id [OWNER] --request-file -`.
- Resumable selection: `task resumable --project-id [ID] --task-type-key [KEY]`.
- Claim: `task claim [ID] --owner-id [OWNER]`, or `task claim-next --project-id [ID] --task-type-key [KEY] --owner-id [OWNER]`.
- Resume: `task resume [ID] --owner-id [OWNER] --claim-version [VERSION] --step [STEP]`; add `--answer-file -` or `--takeover-confirmed` only when required.
- Context: `task context [ID]`.
- Artifact: `task artifact [ID] --step [STEP]`.
- Report: `task report-attempt [ID] --owner-id [OWNER] --claim-version [VERSION] --step [STEP] --outcome [OUTCOME] --artifact-file [FILE]`; add `--message [MESSAGE]`, `--required-checks [STATUS]`, or `--brief-graph-file [FILE]` only when required. Artifact and graph need separate file inputs; use standard input for at most one of them.
- Child observation: `task children [ID]`.
- Child materialization: `task materialize-children [ID] --owner-id [OWNER] --claim-version [VERSION] --definition-file -`.

## Project Discovery

Accept only the canonical repository identity derived by `kos-git`. Use the
public project lookup operation and require its returned identity to equal that
value exactly. Missing or mismatched registration stops before mutation. Never
normalize the lookup value again, accept a near match, infer a project ID, or
create a registration as recovery.

## Results

- Exit `0` means the HTTP operation succeeded. The unchanged server body is on
  standard output and may be empty for a no-content response.
- Exit `1` means an HTTP failure. Preserve the unchanged server body from
  standard output.
- Exit `2` means a usage, configuration, or local-input failure. Read the JSON
  error from standard error.
- Exit `3` means a transport failure. Read the JSON error from standard error.

For a successful JSON operation, parse the complete response and require the
fields needed for the current decision. Malformed, missing, or contradictory
required state is `blocked`; do not invent defaults. Preserve server and CLI
errors without reinterpreting them as workflow outcomes.

## Ambiguous Operations

Reads may be repeated. Never infer that a mutation failed only because its
response was lost. Observe authoritative state before retrying. Retry a mutation
only when help or the server contract makes it idempotent, or observation proves
it did not occur and the same fenced input remains valid. `task create-or-get`
allows one identical retry because the server enforces request identity. If
success or a safe retry cannot be established, stop as `blocked`. After an
ambiguous brief graph materialization, compare the `task children` digest with
the accepted review `graph_digest`. An identical fenced materialization retry is
idempotent and returns `materialization: unchanged`; a conflicting identity must
not be retried. Use `graph_invalid` to retract a wrong unstarted graph before a
new brief and review.

Do not expose administrative project/workflow/task-type operations, task
creation, claim, takeover, resume, cancellation, graph mutation, or arbitrary
CLI execution to a step profile unless that profile's explicit authority
requires the exact focused operation. The shared bearer token is the
authorization boundary; owner and fence checks prevent conflicting trusted
operations but do not authorize agents independently.
