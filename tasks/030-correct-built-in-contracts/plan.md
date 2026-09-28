# Plan

1. Specify explicit built-in catalog revision metadata and upgrade behavior.
2. Update seed installation and readiness checks without mutating old revisions.
3. Correct the `brief` publish instruction and add cross-contract boundary tests.
4. Test idempotent fresh install, catalog upgrade, task revision pinning, and
   readiness.
5. Reconcile documentation and run `bin/check`.
