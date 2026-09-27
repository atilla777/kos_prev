# Run Current Live Acceptance

## Goal

Prove that the remediated current revision completes every supported task type
through installed OpenCode commands, remote publication, released ownership,
and independently observed authoritative state.

## Source Evidence

- Task 014 provides strong live evidence for commit `5bcb29f` and the former
  role-specific agent inventory.
- Task 017 replaced that inventory with generic standard and advanced agents and
  introduced main-agent execution at commit `980294b`.
- Deterministic checks do not prove live model command execution.
- See task 018's `artifacts/readiness-review-2026-09-26.md`.

## Scope

- Install server, CLI, commands, agents, and skills from one exact candidate
  revision using the production procedure from task 024.
- Use isolated API state, data home, OpenCode configuration, fixture repository,
  task worktrees, observer checkout, and bare remote.
- Run real `/kos-brief`, `/kos`, and `/kos-fix` scenarios through terminal
  publication.
- Run the supported custom workflow scenario if task 021 retains executable
  custom workflows.
- Exercise one scheduler interruption/unchanged execution and one expired-lease
  recovery without duplicate publication.
- Retain sanitized but independently verifiable server, graph, Git bundle,
  installed inventory, timing, intervention, and check evidence.
- Evaluate the existing roadmap triggers for combining documentation or adding a
  narrow deterministic Git helper; create later tasks only when evidence meets a
  trigger.

## Out Of Scope

- Fixing newly discovered defects inside the acceptance task.
- Treating sanitized model claims as substitutes for Git and server
  observations.
- Force-pushing or using developer state, credentials, remotes, or databases.

## Acceptance Criteria

- Every supported built-in command reaches `completed` at `publish`, releases
  ownership, and retains the required accepted evidence.
- The exact reviewed commit sequences are observed unchanged in remote history.
- Development and fix publication retain successful structured required-check
  evidence.
- Brief completion has the exact approved bounded child graph and no stranded
  child.
- Generic main/subagent execution and both model tiers are observed from the
  installed candidate inventory.
- Interruption and expired-lease recovery do not loop, duplicate work, commits,
  graph rows, or pushes.
- `bin/check`, production smoke, evidence verifier, Git bundle verification, and
  fixture checks pass on the exact candidate revision.
- Any failure becomes a new planned task; release readiness is not claimed until
  all acceptance criteria pass.
