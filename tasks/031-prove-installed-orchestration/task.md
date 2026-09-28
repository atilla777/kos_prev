# Prove Installed Orchestration

## Goal

Prove that the shipped `/kos` command and `kos-worker` agent can complete the
current agent-led workflow from a clean installed OpenCode configuration rather
than relying only on CLI-level simulations and prose assertions.

## Scope

- Define a reproducible clean-install acceptance scenario for the current
  OpenCode version and managed inventory.
- Exercise project discovery, plan creation, independent worker dispatch,
  reporting, pause and answer, interruption recovery, takeover, and completion.
- Add minimal first-run workflow and plan examples to installation guidance.
- Resolve model/provider portability by either inheriting user configuration or
  documenting and verifying an explicit requirement.
- Retain live-model execution as an operational acceptance exercise unless a
  deterministic regression can be tested locally.

## Out Of Scope

- Evaluating the semantic quality of arbitrary model output.
- Turning OpenCode into a server-managed runtime.
- Encoding a deterministic scheduler in tests or skills.

## Acceptance Criteria

- A recorded clean-install run demonstrates `/kos` coordinating at least two
  independent tasks without executing their substantive steps itself.
- The run demonstrates one durable pause/answer and one fresh-session recovery
  using task 029 discovery.
- Installed assets work without undocumented provider, model, project-ID, or
  plan-key assumptions.
- Installation documentation contains a minimal valid workflow and plan example.
- Stable mechanical regressions discovered by the run have automated tests.
- `bin/check` passes.
