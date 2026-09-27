# Plan

1. Reproduce the production eager-load failure in an isolated temporary data
   home and capture the exact exception.
2. Apply the smallest Zeitwerk-compatible naming or inflection correction.
3. Add positive production boot and eager-load coverage alongside the existing
   configuration tests.
4. Make the required release check run that coverage without relying on an
   externally supplied `CI` value.
5. Update relevant technical documentation, run `bin/check`, and publish the
   completed task.
