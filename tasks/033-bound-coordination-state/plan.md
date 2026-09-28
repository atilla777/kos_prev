# Plan

1. Inventory variable-size persisted and request fields and choose conservative
   MVP limits.
2. Add shared validation constants only where they prevent duplicated policy.
3. Make graph validation iterative and enforce count and byte limits before
   writes.
4. Add exact-boundary, over-boundary, and rollback tests across API and models.
5. Document limits and run `bin/check`.
