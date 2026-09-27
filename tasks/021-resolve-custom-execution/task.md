# Resolve Custom Workflow Execution

## Goal

Make the advertised custom workflow support internally consistent: every
accepted custom workflow is either runnable to a terminal state through a
documented scheduler path or rejected as unsupported.

## Product Decision Required By This Task

Choose and document the smallest coherent contract for custom execution before
implementation. The decision must cover task selection, `main` execution, and
model-tier selection. It may add one generic entry point or deliberately narrow
custom workflow support, but it must not leave server-accepted tasks with no
supported executor.

## Source Evidence

- Installed slash commands schedule only `development`, `fix`, and `brief`.
- Task 017 requires arbitrary custom `main` steps to execute in the current
  command agent, but no custom scheduler entry exists.
- Command frontmatter selects the main-agent model before task context is read,
  so arbitrary custom `main` tiers cannot currently direct that choice.
- Workflow validation allows cycles with no reachable `complete_task`.
- See task 018's `artifacts/readiness-review-2026-09-26.md`.

## Scope

- Decide whether custom task types are executable product behavior or
  administration-only state-machine support.
- If executable, add one documented generic selection/resume path that honors
  execution mode and has an explicit model-tier contract.
- If not executable, reject unsupported definitions or narrow public claims and
  administration accordingly.
- Validate that each accepted workflow has a reachable terminal completion path
  from every reachable non-pause step.
- Add a real custom lifecycle scenario including `main`, `subagent`, backward,
  pause/resume, and completion behavior allowed by the chosen contract.

## Out Of Scope

- A universal workflow language, condition evaluator, or dynamic provider
  configuration.
- Additional built-in task types.
- Weakening built-in completion, check, review, or publication rules.

## Acceptance Criteria

- No public API can create a supported task that has no documented route to an
  executor and terminal completion.
- Main-agent tier semantics are explicit and mechanically testable.
- Workflows with no reachable completion are rejected with a useful error.
- Built-in `/kos`, `/kos-fix`, and `/kos-brief` behavior remains compatible.
- Tests execute at least one custom workflow through the supported entry point;
  model and step-name behavior are not inferred from names.
- Product, architecture, installation, and CLI documentation state the same
  custom support boundary.
- `bin/check` passes.
