# Status

State: done
Updated: 2026-09-28

## Current

The orchestrator now distinguishes planning-only, execution, and ambiguous
intent; discovers workflows before selection; and questions missing explicit
workflow keys without mutation. The brief workflow owns only specification,
review, and publication under built-in catalog revision 3. Runtime cancellation
guidance requires authoritative observation before takeover or later release.

## Decisions

- Explicit planning-only language authorizes plan storage, not execution.
- Unknown workflows are discovered or questioned, never guessed or replaced by
  an ad hoc reduced workflow.
- Keep one generic `/kos` command and narrow `brief` rather than reviving
  `/kos-brief`.
- Ambiguous planning-versus-execution intent is clarified before ready discovery
  or a worker lifecycle mutation.

## Checks

- Focused catalog and skill tests: 13 tests, 238 assertions, passing.
- `bin/check`: 110 tests, 1641 assertions, passing.
- Independent review completed; its intent-ambiguity finding was addressed. The
  existing atomic conflict behavior for an occupied catalog revision remains
  intentionally unchanged and covered.

## Next

Task 038 is the next dependency-ready roadmap item.

## Blockers

- None.
