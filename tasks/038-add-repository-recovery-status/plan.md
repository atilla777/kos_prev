# Plan

1. Specify deterministic checkout and remote resolution while retaining explicit
   project registration and the existing canonical identity rules.
2. Add an injectable local Git-remote reader and thin `project resolve` command
   with precise local, HTTP, and transport errors.
3. Add a read-only aggregate status API or client composition with one stable
   output contract for the resolved project's unfinished plans and tasks.
4. Teach the orchestrator to use status for recovery before creating work while
   preserving explicit takeover decisions.
5. Add isolated CLI, API, Git-fixture, recovery, and documentation tests.
6. Run `bin/check`, obtain independent review, address findings, and publish the
   completed task.
