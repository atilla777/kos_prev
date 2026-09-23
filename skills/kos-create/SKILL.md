---
name: kos-create
description: Use ONLY when the kos or kos-brief scheduler delegates pre-task-ID request-bound creation recovery for /kos-fix or /kos-brief.
---

# KOS Request-Bound Creation

Own only recoverable creation before a task ID is known. Accept exactly a
command kind (`fix` or `brief`) and that command's complete nonblank valid-UTF-8
request. Load `kos-cli` for every KOS operation and `kos-git` only to derive the
invoking checkout's canonical repository identity for `kos-cli` project lookup.
Never use HTTP, Rails, SQLite, an ambient `kos`, or a repository executable.
Never execute a workflow step, dispatch an agent, read or write a step artifact,
inspect a task worktree, operate Git beyond repository identity discovery, or
route workflow state.

On success return only the confirmed positive ASCII-decimal task ID to the
scheduler, with no prose or other field. On any uncertainty stop as blocked and
do not return an ID.

## Canonical Request

Preserve the exact request bytes. Its request digest is the lowercase 64-digit
SHA-256 of those bytes. Split on LF for title selection, remove one terminal CR
from each candidate line only, and select the first line containing a byte other
than ASCII space or tab. Trim only leading and trailing ASCII spaces and tabs,
take at most 120 Unicode scalar values, and prefix `Fix: ` or `Brief: `.

The description is `# Problem\n\n` for `fix` or `# Request\n\n` for `brief`,
followed by the exact request bytes and one LF only if they do not already end
in LF. Do not normalize Unicode, rewrite whitespace, diagnose, infer
requirements, or add acceptance criteria. Use only the stable task type key;
the expected first step is `diagnose` for `fix` and `brief` for `brief`.
The creation key is exactly `request:<kind>:sha256:<request-digest>`. Derive it
from the exact kind and request digest; never generate or normalize it.

Generate a cryptographically unpredictable owner ID unique to this creation
intent. The owner is not a task ID, session PID, timestamp, or request digest.

## Legacy Namespace

Before consulting or creating the current namespace, inspect the baseline
receipt at
`<kos-data-home>/intents/<project-id>/<kind>-<request-digest>-task.json` and
the corresponding intent and lock names without following symlinks. A baseline
receipt contains exactly `kind`, `project_id`, `request_digest`, `owner_id`,
`title`, `description`, and `task_id`; it has no protocol version, repository
identity, request body, task type key, expected first step, or creation key.
Require a regular, single-link file owned by the current user and compare every
available value with the canonical request and exact project.

For an exact baseline receipt, invoke `task show` with its positive task ID and
require the immutable task project, stable type key, title, exact description,
parent, and blockers to match. Return that ID for any lifecycle state before
entering the current creation path. Do not rewrite or delete the baseline
receipt. A near match, malformed file, unsafe path, or contradictory task is
blocked.

If no receipt exists but the exact baseline intent exists, validate its exact
six fields and use `task show-owned` with its owner. Return the ID only for one
exact matching task. A baseline intent without that task, any baseline lock, or
an ambiguous observation is blocked for explicit legacy recovery; never create
a new task while unresolved baseline state exists. This compatibility path is
read-only and exists solely to prevent duplicate tasks from durable state
written by the immediately preceding protocol.

## Private Namespace

Resolve the data home exactly as KOS does: an absolute nonblank `KOS_DATA_HOME`,
otherwise an absolute `XDG_DATA_HOME` plus `/kos`, otherwise
`$HOME/.local/share/kos`. Reject a relative explicit data home. Beneath it use:

```text
creation/<project-id>/<kind>/<request-digest>/
  intent.json
  task.json
  create.lock/
    holder.json
```

The namespace keys are the confirmed project ID, exact kind, and exact request
digest. Directories created by this procedure are mode 0700 and regular files
are mode 0600 regardless of umask. Refuse a symlink or non-directory in every
existing path component from the data home through the request namespace, and
refuse symlinks, hard-linked files, non-regular files, unknown entries, or
wrong ownership/mode in the namespace. Open and inspect without following
symlinks. Never repair an unsafe path or place creation state in a repository.

## Exclusive Lock

Acquire the critical section by atomically creating `create.lock` with mode
0700. Atomically create its mode-0600 `holder.json` from a unique same-directory
temporary file, fsync the file, publish without replacement, and fsync the lock
directory and its parent. The holder contains exactly a fresh lock token, owner
ID, project ID, kind, and request digest. Continue only while the holder token
is this invocation's token.

A concurrent invocation that does not acquire the lock must not create, claim,
resume, or modify files. It may safely observe a valid receipt with `task show`,
or a valid intent owner with `task show-owned`, and compare the complete state
defined below. Exact observation can establish that work exists, but only a
durable matching receipt permits returning its ID. Otherwise report that the
creation owner is still active or the lock is incomplete and stop blocked.

Age, a missing PID, or a timeout never makes a lock stale. Cleanup requires the
user to confirm the prior command process has stopped, then records the lock
directory device/inode and exact holder bytes or confirmed holder absence.
Immediately before cleanup require those facts unchanged. Every entry must be
the exact regular non-symlink `holder.json` or a regular non-symlink temporary
created by this protocol. Remove only those validated entries, fsync the lock,
remove the now-empty lock, fsync its parent, reacquire a new lock, and reread all
state. Never delete a live, changed, foreign, malformed, or unobservable lock.

## Durable Intent

Before `create-and-claim`, atomically publish `intent.json` without replacement.
It contains exactly protocol version, project ID and repository identity, kind,
request digest, creation key, exact request, canonical title and description,
unique owner ID, task type key, and expected first step. Write and fsync a unique
mode-0600 regular temporary file, verify its exact bytes and mode, publish with an atomic
create-if-absent operation such as `link(2)`, fsync the directory, remove only
the temporary name, and fsync again. A crash before publication authorizes no
KOS mutation. An existing intent must match every canonical value exactly;
malformed, duplicate, or contradictory state is blocked.

## Create And Observe

While holding the owned lock, process state in this order:

1. If `task.json` exists, this is a MUST-return-first gate: validate it exactly
   and inspect its positive ID with `task show`. Compare the receipt's immutable
   task identity as defined below,
   but accept any current lifecycle status, step, owner, claim version, lease,
   and accepted-artifact state. Those fields may legitimately change after the
   receipt is published and belong to the scheduler. A cancelled task remains
   the permanent result for that exact request and is returned for explicit user
   handling; never create a replacement silently.
2. Otherwise require the matching intent and invoke `task show-owned` with its
   project and owner. Exactly one matching task proves an earlier ambiguous
   create succeeded. A successful exit with empty standard output is the
   canonical `204 No Content` projection and means no owned task; do not pass
   empty output to a JSON parser. No owned task permits one create attempt. Any
   other task, multiple result, malformed nonempty response, or unavailable
   observation is blocked.
3. Invoke `task create-and-claim` at most once initially, using separate process
   arguments, the stable type key, canonical title, intent owner, deterministic
   creation key via `--creation-key`, and exact canonical description through
   standard input or a verified mode-0600 file in this private namespace. Every
   create-and-claim invocation, including the one permitted retry, must pass that
   same key. Never blindly retry an ambiguous response.
4. After an ambiguous response, call `task show-owned` again. An exact match is
   success; successful empty output again means no task and permits one identical
   retry only while the same intent and owned lock remain valid. Observe once
   more after an ambiguous retry. Anything unavailable, malformed, or
   contradictory is blocked.

Creation is owner-idempotent and server-idempotent by creation key: every
attempt uses the intent's one key, owner, and exact definition. For a create
response or owner observation before `task.json` exists, compare the complete initial projection:
positive task and project IDs,
exact registered repository identity, stable type key, canonical title and
description bytes, intent owner, `active` status, claim version one, future
lease, expected first step, no parent or blockers, and the complete snapshotted
workflow definition.

For an existing receipt, compare only immutable identity against the task:
receipt task ID, project and repository identity, stable type key, canonical
title and exact description, and no parent or blockers. The receipt was
published only after the complete initial workflow projection passed validation,
while the server makes the task's workflow ID and snapshot immutable.
`task.json` intentionally does not duplicate the workflow body, so recovery
must not require an absent workflow field or compare the task with a catalog's
later current revision.

Exact current-namespace receipt validation is versioned. Version 1 is the
pre-key current-namespace format and must
contain exactly `protocol_version`, `project_id`, `repository_identity`, `kind`,
`request_digest`, `request`, `title`, `description`, `owner_id`,
`task_type_key`, `expected_first_step`, and `task_id`. Version 2 contains exactly
those fields plus `creation_key`. New intents and receipts use version 2. For
either version, compare every stored value with the canonical request and exact
registered project; for version 2 also require the deterministic creation key.
Unknown versions, unknown fields, missing fields, and a creation key in version
1 are blocked.

A valid version-1 receipt remains valid; do not rewrite it, require an intent,
or require a field it could not contain. Do not require the intent owner,
initial status, first step, claim version, lease, empty artifacts, or a creation
key on the task referenced by a pre-key receipt. Immediately invoke `task show`
with its positive `task_id`; when immutable identity matches, return that ID
without entering the no-receipt create path. More precisely, return the receipt's
positive task ID without entering the no-receipt create path. Near matches never
recover creation.

## Receipt And Cleanup

After confirming an exact positive task ID, atomically publish mode-0600
`task.json` by the same non-replacing, verified, file-and-directory-fsynced
procedure. It contains exactly every intent field, including creation key, plus
that task ID. An existing byte-identical receipt is success; a different receipt
is blocked. The receipt
may remain permanently as the request-to-task binding, including after task
completion, so the same project/type/request cannot create a duplicate.

Only after the receipt is durable may the owned lock holder remove the matching
intent and temporary description, fsync the namespace, verify its holder token,
remove the holder and lock directory, and fsync the namespace. Interruption at
any cleanup point is recovered from the receipt; never remove the receipt as
ordinary cleanup. Finally re-run `task show`, repeat the receipt's
immutable-identity comparison, and return only its positive decimal task ID.
