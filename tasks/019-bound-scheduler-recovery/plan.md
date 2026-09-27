# Plan

1. Specify per-iteration progress and the bounded outcomes for unchanged,
   expired, paused, and terminal context.
2. Build the smallest executable scheduler harness around fake context, resume,
   main-step, and subagent operations.
3. Update shared scheduler guidance to apply the progress guard and exact resume
   recovery without retaining durable local state.
4. Add crash, stale report, expiry, success, pause, and terminal scenarios.
5. Update product, architecture, and recovery documentation, run `bin/check`,
   and publish the task.
