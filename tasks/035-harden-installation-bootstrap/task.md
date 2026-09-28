# Harden installation and project bootstrap

## Goal

Make a new project's manual registration and a matched KOS/OpenCode installation
easy to establish and verify before orchestration changes coordination or
repository state.

## Scope

- Document the supported administrator bootstrap from a published Git remote
  through `project create` and `project show`.
- Explain canonical repository identity, remote/default-branch requirements,
  checkout ownership, and why KOS does not create repositories or worktrees.
- Add an explicit CLI installation check that compares the OpenCode manifest,
  installed CLI, and server readiness identity before `/kos` or a worker begins.
- Treat missing, malformed, unsupported, stale, or mismatched manifests as
  explicit failures with reinstall guidance.
- Make the installer reconcile files owned by its prior manifest, remove only
  known pre-manifest legacy assets otherwise, preserve unmanaged files, and
  explicitly require an OpenCode restart.
- Improve the project lookup absence response without changing its stable
  `not_found` discriminator.
- Update product, architecture, testing, installation, and user documentation
  plus focused automated coverage.

## Acceptance Criteria

- A clean administrator can register a repository from a complete documented
  example, use the returned canonical identity, and verify it with `project show`.
- Documentation states that a remote repository and chosen default branch are
  required metadata, while cloning, initial commits, publication, GitHub
  creation, and worktree management remain external responsibilities.
- The supported OpenCode workflow checks one successful manifest marker and
  rejects missing or invalid metadata, wrong inventory, and any version or
  `source_id` disagreement among manifest, CLI, and `/ready` before project or
  task operations.
- A matching but unavailable server is distinguished from an incompatible
  installation.
- Reinstallation removes current-release stale assets listed by a valid prior
  manifest and the finite known pre-manifest legacy inventory while preserving
  unrelated user files.
- The installer tells the operator to fully restart OpenCode.
- Tests cover clean installation, legacy upgrade, manifest reconciliation,
  missing/invalid/mismatched manifests, compatibility success/failure, project
  bootstrap lookup, and unmanaged-file preservation.
- `bin/check` passes and an independent review finds no unresolved correctness
  issue.

## Non-Goals

- Restore legacy scheduler commands, role agents, or workflow-specific skills.
- Create local or GitHub repositories, choose among Git remotes, create initial
  commits, publish branches, clone repositories, or manage worktrees.
- Introduce a compatibility matrix, rolling mixed-release support, or automatic
  migration from the retired architecture.
