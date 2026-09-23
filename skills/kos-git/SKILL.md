---
name: kos-git
description: Use for KOS task worktree derivation, centralized Git policy, publication, and independent remote verification from one task ID.
---

# KOS Git Protocol

## Repository Discovery

Before task mutation or any local recovery-state or worktree mutation, inspect
the invoking checkout's `origin`. Require exactly one configured fetch URL from
`git remote get-url --all origin` and exactly one configured push URL from `git
remote get-url --push --all origin`; an absent `origin`, zero URLs, or multiple
URLs is `blocked` without mutation.

Normalize each URL to canonical `host/namespace/repository`. Accept only HTTPS,
`ssh://git@host/namespace/repository`, and relative scp-style
`git@host:namespace/repository`; lower-case the host and remove one terminal
`.git`. Reject local and `file:` paths, credentials, non-`git` SSH users,
queries, fragments, ports, controls, whitespace, missing namespace or repository
components, an absolute scp path such as `host:/namespace/repository`, and a URI
path with duplicate or ambiguous leading slashes. Fetch and push spellings may
differ only when both normalize to the same identity.

Before a task ID exists, a scheduler or `kos-create` returns that canonical
identity to `kos-cli` for exact project lookup. After a step agent has a task ID,
compare the discovered identity directly with the registered identity in `task
context`; do not call `project show`. A fetch/push identity mismatch or any
absent, malformed, unsafe, or ambiguous URL stops before task or local recovery
mutation. Do not choose a similarly named project, infer a numeric project ID,
or create a registration.

## Authoritative Context

Accept only a positive task ID. Load `kos-cli` and derive the project ID,
registered identity, remote, default branch, task title, current step, and execution
authority from `task context ID`. Never accept paths, commands, a diff, changed
files, project identity, or Git facts from the dispatcher. Derive the worktree
as `<kos-data-home>/worktrees/<project-id>/<task-id>` and verify it belongs to
the registered repository and remote. Refuse symlinks, foreign registrations,
ambiguous remotes, identity mismatches, invalid branches, active Git operations, or divergent
history without repairing or deleting anything.

Create a missing detached worktree from the freshly fetched default branch.
Reuse an existing one only after verifying its common Git directory,
registration, detached HEAD, ancestry, and complete status. Preserve staged,
unstaged, and untracked task work. Never clean, prune, force-push, delete an
unexpected path, or discard changes.

## Step Policy

The exact authoritative current step controls Git authority:

- `diagnose`, `plan`, `review`, and `verify` are read-only. HEAD and complete
  status must remain byte-for-byte unchanged.
- `implement` and `document` may mutate the task worktree but must not commit or
  push. HEAD must remain unchanged.
- `brief` may change only the specification and task-graph work authorized by
  its profile, without commit or push.
- `publish` alone may update a moved base, stage, commit, and push.
- Unknown custom steps may never commit or push unless a separately installed
  profile grants exact publication authority.

Centralize all Git observation and mutation here. Step profiles must not invent
alternate commit, base-update, push, or recovery procedures.

## Publication

At `publish`, fetch and observe the remote before mutation. Validate the task
diff against the accepted plan, implementation, documentation, and review
artifacts obtained through `kos-cli`. For a brief, also validate the accepted
graph and reviewed specification and preserve publication-before-materialization.
If review evidence is invalid, do not publish and return `review_invalid`.

If the default branch moved forward, use only `git checkout --merge --detach`
to preserve task content on the new detached base and return `base_moved`
without committing. Otherwise stage only validated
task paths, inspect the complete staged patch, run `git diff --cached --check`,
and create one commit using a safe whitespace-free path in the exact command
`git commit -F <verified-message-file>`, with no trailing argument, so task text
is never shell syntax:

```text
KOS task <task-id>: <normalized title>

KOS-Task: <task-id>
```

Require one parent at the fetched base, one exact trailer, exact expected changed
paths, a nonempty tree change, and a clean worktree. Push only exact
`HEAD:refs/heads/<validated-default-branch>` to `origin` as one plain command,
without options, extra refspecs, Git configuration prefixes, shell composition,
or force; fetch again regardless of push output, and report
`published` only when the candidate is observed in remote history. Recover an
interrupted publication by observation before retrying; never create a duplicate
commit.

## Independent Verification

At `verify`, perform no mutation: no checkout, index change, commit, push,
materialization, or worktree edit. Independently fetch the remote branch, locate
the published commit, require exactly one `KOS-Task: <task-id>` trailer, inspect
its changed paths and patch, and compare the remote result with the task and
accepted artifacts. Do not trust the publish artifact or local HEAD as proof.

Return `publication_missing` when no valid task commit is remotely observable.
Return `changes_invalid` for a development or fix result that does not satisfy
the accepted task evidence. For brief tasks, verify both remote specification
publication and the server-observed child graph. Return
`materialization_missing` only when publication is valid but the exact accepted
graph is absent. Return `brief_invalid` only when correction can safely restart
briefing before any child graph exists; if children already exist, use
`blocked` rather than redefining them. Only complete remote and result evidence
permits `verified`.

Return observed facts to the current step agent. This skill never reports a KOS
attempt and never executes another workflow step.
