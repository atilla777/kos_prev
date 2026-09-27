# Evaluate Document Consolidation

## Goal

Decide whether development and fix documentation should remain a separate step
after current live evidence showed repeated no-op execution, and implement only
the smallest safe workflow reduction if product-specification maintenance stays
equally strong.

## Source Evidence

- Task 025 development documentation reported that the brief specification
  already covered the implementation and created no commit.
- Task 025 fix documentation reported that behavior was restored to the existing
  specification and created no commit.
- The roadmap decision permits reconsideration when documentation is repeatedly
  a no-op and consolidation would not weaken specification maintenance.

## Scope

- Compare the separate document step with implementation-owned OKF maintenance
  for development and fix workflows.
- Preserve mandatory product-behavior updates before independent review.
- Measure dispatch, recovery, evidence, and compatibility consequences.
- If consolidation is safe, update canonical workflows, instructions, tests,
  installation contracts, and specifications with no legacy dual path.
- If it is not safe, record the concrete invariant requiring a separate step
  and close the trigger without implementation churn.

## Out Of Scope

- Changing brief review or publication.
- Weakening independent review, required checks, or exact-range publication.
- Addressing stale-report behavior owned by task 026.

## Acceptance Criteria

- The decision is supported by deterministic workflow analysis and task 025
  evidence.
- Product behavior changes still update OKF before independent review.
- Any workflow change preserves immutable existing task revisions and updates
  clean-install assets and scenario coverage.
- `bin/check` passes, and focused live evidence is retained if execution shape
  changes.
