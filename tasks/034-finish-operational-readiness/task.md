# Finish Operational Readiness

## Goal

Remove remaining misleading legacy contracts and make installation, health
checks, backup, restore, and verification reproducible for the supported
single-host deployment.

## Scope

- Reject relative explicit OpenCode configuration paths before expansion and
  define behavior for relative `XDG_CONFIG_HOME`.
- Remove obsolete worktree-path test support and stale local environment keys.
- Replace brittle prose-literal agent tests with stable inventory and boundary
  assertions.
- Align testing documentation with actual coverage.
- Document `/ready`, a production launch command, service supervision, TLS proxy
  expectations, filesystem ownership, backup restore, and secret rotation.
- Decide and document the pre-release tagging and release verification process.

## Out Of Scope

- High availability, multi-host SQLite, Kubernetes packaging, or a web UI.
- General-purpose deployment automation for every operating system.
- Changing the core agent-led lifecycle without a reproduced defect.

## Acceptance Criteria

- The installer rejects relative explicit destinations without modifying files.
- Tests contain no contract for removed KOS-managed worktree behavior or stale
  PLAN-022 environment settings.
- Agent tests verify durable role boundaries without depending on harmless line
  wrapping or exact prose.
- An operator can start, probe, back up, restore, rotate credentials for, and
  roll back the supported deployment using the documented commands.
- Public liveness and readiness endpoints are documented consistently.
- Release verification includes `bin/check` and the task 031 acceptance record.
- `bin/check` passes.
