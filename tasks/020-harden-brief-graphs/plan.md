# Plan

1. Specify graph identity, retry, correction, cancellation, and size-limit
   semantics before changing persistence.
2. Add failing lifecycle and concurrency tests for wrong graph recovery,
   cancellation after materialization, exact retry, and oversized graphs.
3. Implement the smallest schema and transaction changes that bind graph
   identity and preserve atomic observation.
4. Bound normalization and cycle validation, using an iterative algorithm where
   recursion could exceed accepted limits.
5. Update CLI projections, workflow instructions, and normative contracts.
6. Run `bin/check`, complete the records, and publish the task.
