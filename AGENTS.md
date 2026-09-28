# Agent Rules

## Development Tasks

KOS is developed through the repository files under `tasks/`, not through a
running KOS task. Do not invoke `/kos` to coordinate changes to this repository.

`tasks/roadmap.md` is the authoritative ordered task list. When asked to do the
next task, select the first `planned` task whose dependencies are `done`. Work on
only one active task at a time.

Each task directory contains:

- `task.md` for the stable goal, scope, and acceptance criteria;
- `plan.md` for the current implementation plan;
- `status.md` for progress, checks, blockers, and the next action; and
- an optional `artifacts/` directory for useful evidence.

The files are lightweight development records, not a strict schema and not KOS
runtime state. Keep them concise. Update `status.md` as work progresses and keep
the summary state in `tasks/roadmap.md` consistent with it.

After a task's scope is approved, continue autonomously through implementation,
verification, task-file updates, commit, push without force, and independent
remote observation. Stop only when publication is observed successfully, a
product decision requires the user, or a technical blocker prevents safe
progress.

## Project Contracts

Read these documents before changing behavior or architecture:

- `specs/index.md`
- `docs/specification.md`
- `docs/architecture.md`
- `docs/testing.md`
- `CONTRIBUTING.md`

Work only on the active task. Do not implement later roadmap items
opportunistically. Make the smallest coherent change that satisfies its
acceptance criteria, update relevant tests and documentation, and run
`bin/check` before publication.
