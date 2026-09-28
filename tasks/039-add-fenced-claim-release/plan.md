# Plan

1. Specify release semantics and fences alongside claim, takeover, report,
   answer, and plan abandonment.
2. Implement one transactional lifecycle operation that returns an exact active
   claim to pending and advances task and plan versions.
3. Expose the operation through the authenticated API and thin CLI with complete
   help and stable conflict behavior.
4. Update orchestrator cancellation guidance to use release only for its exact
   known stopped dispatch; retain takeover for immediate replacement.
5. Add state, stale-worker, race, rollback, restart, API, CLI, and skill tests.
6. Run `bin/check`, obtain independent review, address findings, and publish the
   completed task.
