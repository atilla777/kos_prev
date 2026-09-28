# Status

State: done

## Diagnosis

- The server derives `repository_identity` from `remote_url`; the canonical form
  includes the lowercased host, for example `github.com/acme/widget`.
- `remote_url` and `default_branch` are required project metadata, but KOS does
  not inspect Git, create repositories, clone, publish, or manage worktrees.
- `project show` correctly returns the stable `not_found` discriminator for an
  absent exact identity, but installation examples omitted the host and offered
  no actionable explanation.
- The CLI, `/ready`, and `kos-installation.json` expose the same version and
  source identity, but no supported runtime operation compares them.
- The installer writes its manifest last as a success marker but does not read a
  prior manifest, so future inventory changes and rollback can leave stale
  managed assets. The current hard-coded list does cover all known historical
  KOS integration names.
- Reinstalling files cannot refresh assets already cached by a running OpenCode
  process; the installer output does not currently state that a full restart is
  required.

## Decisions

- Keep project registration explicit and administrator-owned. Add no Git-aware
  init command or automatic repository/worktree creation.
- Use exact version and `source_id` equality for the pre-release single-release
  installation instead of introducing backward compatibility or a protocol
  matrix.
- Preserve the `not_found` machine discriminator and add project-specific
  guidance as an additive field.
- Use a valid prior manifest as ownership metadata. With no prior manifest,
  remove only the finite reserved legacy KOS names and preserve all other files.

## Result

- Added `installation check` to validate the successful OpenCode manifest,
  packaged CLI, server release identity, and readiness before orchestration.
- Made installer updates reconcile valid prior ownership, reject unowned current
  collisions and unsafe manifests, preserve unrelated files, migrate the finite
  pre-manifest KOS inventory, and require a full OpenCode restart.
- Documented complete project registration and verification, canonical identity,
  remote/default-branch prerequisites, and the external Git/worktree boundary.
- Preserved the stable `not_found` discriminator while adding project-specific
  registration guidance.

## Checks

- Focused CLI, installer, API, and skill tests passed.
- `bin/check` passed after review: 103 tests, 1342 assertions, no failures.
- Independent review found three issues around destination ownership, manifest
  namespace trust, and CLI error-stream documentation. All were corrected; the
  follow-up review reported no correctness or security findings.

## Residual Risk

A structurally valid local manifest is trusted to own names in the reserved
`kos*` and `okf` namespace. KOS does not attest a running OpenCode process, so a
full restart remains required to replace assets already loaded in memory.
