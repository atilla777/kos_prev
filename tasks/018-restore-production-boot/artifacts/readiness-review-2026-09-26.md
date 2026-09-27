# Readiness Review Evidence

Date: 2026-09-26
Reviewed revision: `980294b Make workflow execution generic`
Review mode: read-only source, contract, test, roadmap, and retained-evidence
inspection. The worktree was clean and `HEAD` matched `origin/main`.

## Verdict

The state core is coherent and well tested, but the reviewed revision is not
ready for production use. Built-in lifecycle behavior is strong at the Rails
boundary; release blockers and liveness gaps remain at production boot,
scheduler recovery, brief materialization, installed runtime execution, and
operations. Current generic-agent execution lacks live evidence on the reviewed
revision.

## Confirmed Findings

### Production boot

- `config/environments/production.rb:9-10` enables eager loading.
- `config/application.rb:28-31` includes `lib` in autoloading.
- `lib/kos/cli.rb:9-10` defines `Kos::CLI`; Zeitwerk derives `Kos::Cli` from
  `cli.rb` without an acronym.
- `config/initializers/inflections.rb:13-16` contains only commented examples.
- `test/integration/configuration_test.rb:67-87` positively boots development;
  `:109-127` only proves production rejects a missing token.

### Scheduler liveness and recovery

- `skills/kos/SKILL.md:36-49` dispatches and rereads context in an unbounded
  loop, with no before/after progress check.
- A child crash, rejected report, or lease expiry can leave the task `active` at
  the same step. Re-dispatch then repeats work and can continue indefinitely.
- `app/models/task_lifecycle.rb:221-224` correctly rejects an expired report,
  but the scheduler does not convert that state into bounded resume recovery.
- Server fencing is sound; the missing behavior is scheduler-side liveness.

### Brief graph terminal states

- `app/models/brief_task_graph.rb:13` rejects every second materialization after
  any children exist.
- `app/models/task_lifecycle.rb:399-410` prevents publication rewinds after
  materialization.
- `app/models/task_lifecycle.rb:230-250` still permits cancellation of the
  materialized parent.
- `app/models/brief_task_graph.rb:25-29` blocks every child on that parent, and
  `app/models/task_lifecycle.rb:263-267` only makes a task eligible when all
  blockers are completed. Cancelling the parent therefore strands its children.
- The graph payload is not mechanically bound to an accepted structured review
  identity. A valid but accidentally wrong graph cannot be corrected through a
  documented path.
- `app/models/brief_task_graph.rb:75-129` has no child, edge, depth, or field-size
  limits. Cycle detection is recursive and dense materialization is quadratic.

### Custom workflow completion

- `skills/kos/SKILL.md:21-25` selects only `development`, `fix`, or `brief`.
- `.opencode/commands/kos.md:7-9` accepts no arguments and only schedules
  development tasks.
- No installed command schedules an arbitrary custom task type or exact custom
  task.
- `tasks/017-generic-workflow-execution/task.md:84-85` nevertheless requires a
  custom `main` step to execute in the command agent.
- `app/models/workflow.rb:47-69` validates shape and transition targets but not
  whether completion is reachable. A valid custom workflow may be permanently
  nonterminal.
- Main-agent model selection occurs in command frontmatter before context is
  read, so arbitrary custom `main` tiers need an explicit product contract.

### Runtime boundaries

- Scheduler-facing create, claim, resumable, and resume operations use the
  broad serializer in `app/controllers/tasks_controller.rb:227-238`, exposing
  description Markdown and the complete workflow definition despite the
  scheduler boundary in `docs/specification.md:84-88`.
- `test/skills/kos_skills_test.rb:135-146` checks scheduler prose, not actual
  scheduler-facing response projections.
- `skills/kos-git/SKILL.md:35-40` derives worktrees from `<kos-data-home>`, but
  the client-side source of that value is undefined.
- `docs/installation.md:94-101` omits `KOS_DATA_HOME` from the OpenCode terminal,
  so a nondefault server data home can produce a different client path.
- `config/kos.rb:25-29` accepts any nonblank API token, while
  `lib/kos/cli.rb:502-507` additionally requires valid UTF-8 and rejects CR/LF.

### Test evidence

- `tasks/014-simplified-live-acceptance/artifacts/summary.md:7-9` records complete
  live scenarios at commit `5bcb29f` using the former role-specific profiles.
- The reviewed `980294b` revision introduced generic profiles and main-agent
  execution after that evidence.
- `tasks/017-generic-workflow-execution/status.md:19-24` records deterministic
  `bin/check`, but no current-revision live model run.
- `test/integration/plan_022_acceptance_matrix_test.rb:71-74` labels direct
  lifecycle tests as real E2E although they do not execute OpenCode scheduling.
- `test/skills/kos_skills_test.rb:109-160` primarily verifies strings in managed
  Markdown rather than executing scheduler control flow.

### Operations

- `docs/installation.md:85-92` starts the default development server, not a
  documented production service.
- Production assumes TLS termination in
  `config/environments/production.rb:21-25`, but no matching process, proxy, or
  certificate deployment is documented.
- `config/routes.rb:2` exposes the default Rails `/up`; it does not establish
  database writability, migration state, built-in catalog presence, or data-home
  readiness.
- No remote CI workflow is checked in. `bin/ci` and `config/ci.rb` are local and
  do not run the complete `bin/check` contract.
- The upgrade guide says to back up state but has no consistent SQLite backup,
  restore verification, or rollback procedure.
- CLI release identity remains `0.1.0` without revision provenance, making mixed
  installed revisions difficult to diagnose.

## Complexity Assessment

The five-table Rails state core, immutable workflow snapshots, atomic report,
ownership fence, pause binding, and request idempotence are justified and do not
appear overengineered. Complexity and reliability risk are concentrated in the
prose-controlled delivery boundary:

- `app/models/built_in_catalog.rb:2-10` asks models to implement exact-range Git
  validation, read-only review, digest verification, remote classification, and
  publication.
- Rails intentionally validates lifecycle and required-check assertions but not
  Git evidence semantics.
- Backward transitions preserve later accepted artifacts, so executors must
  distinguish stale downstream evidence correctly.
- The separate documentation step may become a recurring no-op; the existing
  reconsideration trigger is recorded in `tasks/roadmap.md:39-45`.

Do not add a deterministic Git helper solely from this review. The existing
decision in `tasks/roadmap.md:53-70` requires an unsafe result, two Git-specific
interventions, or significant measured cost. Current live acceptance should
measure those triggers and create a focused helper task only if one occurs.

## Strong Existing Guarantees

- Atomic artifact and transition updates with owner, step, claim-version, and
  lease fencing.
- Exact pause and human-answer binding that survives restart.
- Request-bound create-or-get idempotence through a scoped unique key.
- Required-check gates for development and fix implementation, review, and
  publication.
- Immutable used workflow revisions and protected built-in task types.
- Atomic brief graph creation and serialization with publication reporting.
- Strong deterministic Git fixtures for linear ranges, trailers, trees, paths,
  binary diff digests, moved bases, and ambiguous push recovery.

## Ordered Remediation

1. Restore production boot and eager-load coverage in task 018.
2. Bound scheduler dispatch and recover expired claims in task 019.
3. Make brief materialization safe, recoverable, and resource bounded in task
   020.
4. Resolve and implement the custom workflow execution contract in task 021.
5. Tighten scheduler projections, data-home discovery, and token consistency in
   task 022.
6. Execute real scheduler control flow in deterministic tests and correct the
   acceptance claims in task 023.
7. Complete production operations, readiness, CI, backup, and release identity
   in task 024.
8. Run all three live slash-command scenarios on the resulting revision and
   retain independently verifiable evidence in task 025.
