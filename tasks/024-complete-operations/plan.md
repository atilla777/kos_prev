# Plan

1. Choose the minimal supported single-host production topology and document its
   process, environment, proxy, and restart boundaries.
2. Implement and test focused liveness and readiness endpoints.
3. Add a clean production installation/start smoke test and remote CI workflow
   that invokes `bin/check`.
4. Define build revision provenance across server checkout, gem, and installed
   OpenCode inventory.
5. Write and rehearse SQLite backup, integrity, restore, upgrade, and rollback
   procedures with isolated state.
6. Review logging and secret filtering, run `bin/check`, and publish the task.
