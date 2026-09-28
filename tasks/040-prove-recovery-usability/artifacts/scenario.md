# Recovery Usability Scenario

## Isolation

The run used separate temporary directories for the production database, gem
installation, OpenCode configuration, and fixture checkout. The CLI gem and
managed OpenCode inventory were built from candidate commit `1981c2e`. The
fixture was published at
`https://github.com/atilla777/kos-recovery-acceptance-040` before registration.
Provider credentials were inherited by OpenCode and were not retained.

## Discovery

The installed CLI passed `installation check` against the isolated manifest and
server. Before plan creation it listed the three built-in revision 3 workflows,
showed the complete workflow schema and example, and printed plan construction
help. No source file was inspected and no fallback workflow was created.

## Planning Only

A `/kos` invocation from the fixture checkout explicitly selected remote
`origin` and requested planning only. It created one plan containing independent
Alpha and Beta tasks bound to `development` revision 3. The session stopped
after `plan put`; both tasks were pending at `plan`, version 0, without claims.
The local and remote fixture remained at the initial commit.

## Cancellation And Release

A later `/kos` invocation explicitly authorized execution. It claimed both
tasks and dispatched workers. After Alpha reported only its plan, the OpenCode
process was stopped while Beta's plan worker remained active. Authoritative
status before and after process termination was identical.

Beta's exact stopped envelope was released. The task moved from active version 1
to pending version 2 at the same `plan` step, its claim was cleared, and the plan
version advanced from 3 to 4. A report using the released envelope was rejected
as stale and did not change state.

A second execution process claimed Alpha at `implement` and Beta at `plan`; it
was stopped before either worker changed repository or coordination state. This
left two active claims for the fresh-session recovery exercise.

## Fresh Recovery

A new `/kos` invocation received neither a project ID nor a plan key. Its first
authoritative recovery read was `status --remote origin`, which returned the
registered project, the same plan, and both active task fences. Given explicit
confirmation that the old process and workers had stopped, it took over both
tasks with new claims.

Workers completed the existing development workflows through implementation,
independent review, and publication. Alpha published commit `182c725`, then Beta
published commit `107e141`. Default recovery status became empty because both
tasks completed. An independent remote read resolved `origin/main` to
`107e141a363d17802d648a32b5f7c1d762e2c8a1`, and the retained bundle reproduces
that history.

## Evidence Hygiene

Raw OpenCode JSON streams, mutable SQLite files, bearer credentials, provider
configuration, session identifiers, and raw claim IDs are not retained. Stream
hashes commit to the discarded transcripts. `events.json` retains the actual
CLI and worker tool events needed to inspect ordering and outputs, with source
line hashes, hashed claims, and redacted session identities. The Git bundle
necessarily retains the public author and committer metadata of the published
fixture commits.
