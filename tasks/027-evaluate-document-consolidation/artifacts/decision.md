# Document Consolidation Decision

Date: 2026-09-27

## Decision

Remove the separate `document` step from new canonical development and fix
workflow revisions. Make `implement` own product-behavior maintenance before
independent review.

## Evidence

- Task 025 development and fix runs both completed documentation as no-op
  validations because the applicable OKF behavior was already correct.
- The document step had no server-enforced semantic gate. Its guarantees came
  from its instruction, artifact, Git state, and the following independent
  review.
- Existing implementation already owns repository mutation, required checks,
  the clean task-owned commit range, and moved-base integration. Updating OKF in
  the same content step does not expand its mutation boundary.

## Preserved Invariants

- Implementation must use `okf` to update affected product behavior before
  review, or record why behavior did not change.
- Independent review must reject missing or incorrect product-behavior
  maintenance through `changes_requested`, which returns to implementation.
- Required-check gates, read-only independent review, exact-range publication,
  and moved-base recovery remain unchanged.
- Catalog installation creates new immutable workflow revisions. Existing tasks
  retain their prior revision, including `document`, without a dual runtime path.

## Consequences

Each successful development or fix pass removes one standard subagent dispatch,
one accepted artifact, one claim-version transition, and one scheduler recovery
boundary. The implementation artifact now carries product-behavior evidence;
review and publication continue to validate the complete aggregate commit range.
