# Plan

1. Specify the smallest plan-level terminal state and optimistic fence required
   for abandonment.
2. Implement one atomic lifecycle operation and its API/CLI projection.
3. Integrate abandonment with readiness, discovery, context, and worker fencing.
4. Add concurrency and restart tests against claim, report, answer, and takeover.
5. Update role guidance and documentation, then run `bin/check`.
