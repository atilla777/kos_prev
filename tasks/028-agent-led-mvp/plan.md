# Plan

1. Inventory the current PLAN-022 data, API, CLI, workflow, skill, and test
   contracts against `specs/kos.md`; classify each mechanism as retain,
   simplify, replace, or remove.
2. Specify the minimal generic state model and public operations for atomic
   plan storage, dependency readiness, claim, explicit takeover, context,
   report, pause, answer, and completion.
3. Simplify the Rails lifecycle and schema, removing lease recovery and all
   built-in-only check, Git publication, and brief-graph semantics.
4. Simplify the CLI to expose the generic operations without duplicating domain
   validation or recovery algorithms.
5. Rewrite the scheduler and worker skills so the orchestrator only coordinates,
   workers execute one substantive step, and independent tasks can be dispatched
   concurrently.
6. Reduce built-in workflows to concise defaults over the generic mechanism and
   remove version-specific argument framing and deterministic Git procedures
   from agent instructions.
7. Replace obsolete harness and prose-literal coverage with focused production
   contract tests, then update all normative and operational documentation.
8. Run `bin/check`, inspect the final diff for residual PLAN-022 complexity, and
   record any deliberately deferred non-MVP concern without implementing it.
