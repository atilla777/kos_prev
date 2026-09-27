# Plan

1. Reproduce one stale live report while retaining sanitized submitted and
   authoritative fence values.
2. Trace context reads and report construction to the first divergent value.
3. Add the smallest deterministic regression coverage and implementation fix.
4. Re-run focused installed development, fix, and custom recovery paths.
5. Verify fencing invariants, run `bin/check`, and publish the evidence.
