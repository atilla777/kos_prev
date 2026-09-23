---
name: kos-cli
description: Use for focused KOS CLI discovery, compatibility checks, safe invocation, projection validation, and ambiguous-operation recovery.
---

# KOS CLI Protocol

## Discover

Use only the absolute administrator-configured `KOS_CLI_PATH`; never use an
ambient `kos`, a repository executable, the REST API, Rails, or SQLite. Require
an executable regular file. Check it only with a separate shell builtin `test`
using `KOS_CLI_PATH` (`-n`, absolute-path shape, `-f`, and `-x`); do not use
Python, Ruby, command substitution, or another wrapper for this validation.
Validate `--version` and top-level `--help`, then
validate `--help` for each operation before its first use. Pass every value as a
distinct process argument. Never print `KOS_API_TOKEN`, put it in arguments, or
expose a credential-bearing URL.

Run exactly one CLI process in each shell tool call. Never combine validation or
operations with `&&`, `;`, a pipeline, command substitution, a shell wrapper, or
another command. Focused profile permissions intentionally match each absolute
CLI invocation separately and reject composite command strings.

Require the installed CLI to provide selection and creation operations needed
by slash commands, plus these focused step operations:

- `task context ID`: authoritative task, workflow, current step, execution
  identity, accepted-artifact index, registered project, pause message and
  answer, and status;
- `task artifact ID --step STEP`: one accepted Markdown artifact for that task
  and step, or an explicit absent result;
- `task report-attempt ID --owner-id OWNER --claim-version VERSION --step STEP
  --outcome OUTCOME --artifact-file FILE [--message MESSAGE]`: one atomically
  stored Markdown artifact and workflow transition. `FILE` may be `-` for
  standard input; `MESSAGE` is required by procedure for a pause.

Missing operations or incompatible options are `blocked` before mutation. Do
not emulate them with old `task show`, local artifact paths, direct HTTP, or
database access.

## Project Discovery

For repository-based project discovery, cooperate with `kos-git`: accept only
the canonical identity it derives from the invoking checkout's single `origin`
fetch URL and single `origin` push URL. Validate `project show
--repository-identity IDENTITY` before first use, invoke that exact lookup, and
require the returned complete project projection's `repository_identity` to
equal `IDENTITY` byte-for-byte. Do not normalize the lookup value in the CLI,
search by remote URL, accept a near match, or infer a numeric project ID.

An absent registration, malformed projection, mismatched identity, unavailable
lookup, or ambiguous Git origin stops before every task mutation and before
intent, receipt, answer, artifact, or worktree recovery mutation. A not-found
response is an explicit missing registration, not permission to create one;
project creation and in-place update remain administrative operations.

## Validate Projections

Accept successful output only as complete valid UTF-8 JSON matching the exact
operation projection. Reject unknown or missing required fields, wrong scalar
types, nonpositive IDs, unsafe step IDs, duplicate workflow steps, a current
step absent from the snapshotted workflow, unsupported model tiers, malformed
outcome actions, project mismatches, expired claims, or contradictory status,
owner, question, reason, artifact, and action data. Preserve stable server
errors without reinterpretation.

`context` is authoritative for dispatch and reporting. Its artifact index names
only accepted step, outcome, claim version, and reconstruction state; fetch
Markdown separately. `artifact` returns the requested accepted outcome,
Markdown, claim version, and reconstruction state; HTTP absence is not an empty
artifact. `report-attempt` returns the ordinary resulting task envelope. Require
exactly one claim-version increment and the expected status, step, and ownership
for the selected action, then use `context` for accepted-artifact observation.

## Invoke Safely

Use standard input for secret-free structured Markdown whenever supported. If a
file is required, create a mode-0600 regular file in a private temporary
directory outside every repository, write exact bytes without interpolation,
pass its path as one argument, and remove it after an unambiguous response.
Never use local task artifact directories.

Read operations may be retried after validating that they have no mutation.
Never blindly retry a mutation. After an ambiguous claim, create, resume,
materialization, or report, invoke the operation-specific read projection and
compare exact authoritative state. Retry once only when that observation proves
the mutation did not occur and the same fenced input remains valid. An observed
transition is success; unavailable or contradictory state is `blocked`.

Do not expose administrative project/workflow/task-type operations, task
creation, claim, takeover, resume, cancellation, graph mutation, or arbitrary
CLI execution to a step profile unless that profile's explicit authority
requires the exact focused operation. Server authorization and fencing remain
the final enforcement boundary.
