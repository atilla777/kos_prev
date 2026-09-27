# Status

State: done
Updated: 2026-09-27

## Current

Approved brief review evidence now stores the normalized graph and authoritative
digest. Materialization compares that identity, exact retries return unchanged,
conflicts preserve the existing graph, and completion compares the observed
digest mechanically.

`graph_invalid` atomically retracts only an unclaimed pending graph. Cancelling a
materialized brief atomically cancels unfinished children. Validation is bounded
to 64 children, 256 sibling edges, depth 32, 100-byte keys, 200-byte titles,
16 KiB descriptions, and 1 MiB canonical JSON, with iterative cycle/depth checks.

## Next

Task 021 may proceed.

## Blockers

None.

## Checks

- `bin/check`
- 266 tests, 3947 assertions, 0 failures, 0 errors, 0 skips.
- Independent review completed; all findings were addressed.
